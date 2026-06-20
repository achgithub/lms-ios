// Generic request-triggered freshness gate — the versioned counter-pair pattern
// (spec §4.2 / §10.2), generalised from the original score-only cache so that
// scores, fixtures and standings all share one code path.
//
// Each gated resource keeps a counter pair plus a timestamp in KV:
//   <res>:call     integer, bumped by the first caller that sees staleness
//   <res>:refresh  integer, set equal to call once the upstream write lands
//   <res>:ts       ISO8601, when call was last bumped (the time gate)
//
// State machine (per resource):
//   call == refresh, fresh  -> serve current store, no upstream call
//   call == refresh, stale  -> bump call, serve current store now, refresh in bg
//   call >  refresh         -> refresh in flight; serve current store now, poll
//
// The gate only governs *when* to re-pull upstream. WHERE the data lives is the
// caller's business: scores cache their payload in KV, fixtures/standings serve
// straight from D1. Either way the current (possibly stale) data is served
// immediately — the user never blocks on upstream — and the next request inside
// the window is served from the warmed store. Result: ~1 upstream call per TTL
// window per resource regardless of concurrent users.

import { getSeasonPhase } from "./seasonPhase";

// Minimal structural type — we only need waitUntil, so we don't couple to the
// exact ExecutionContext shape (which differs between Hono and the workerd
// runtime types). Both Hono's c.executionCtx and the global ctx satisfy this.
export interface BackgroundCtx {
  waitUntil(promise: Promise<unknown>): void;
}

// KV key triple for one gated resource.
export interface GateKeys {
  call: string;
  refresh: string;
  ts: string;
}

// Scores additionally cache their payload in KV under this key (fixtures and
// standings keep their data in D1, so they need no data key).
export const SCORES_DATA_KEY = "scores";

export const SCORES_KEYS: GateKeys = {
  call: "scores:call",
  refresh: "scores:refresh",
  ts: "scores:ts",
};
export const FIXTURES_KEYS: GateKeys = {
  call: "fixtures:call",
  refresh: "fixtures:refresh",
  ts: "fixtures:ts",
};
export const STANDINGS_KEYS: GateKeys = {
  call: "standings:call",
  refresh: "standings:refresh",
  ts: "standings:ts",
};

const MAX_RETRIES = 5; // 5 × 1s = 5s max background poll

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseInt0(v: string | null): number {
  const n = parseInt(v ?? "0", 10);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Run a resource's freshness check. If the window is stale this Worker claims the
 * refresh (bumps `call`, stamps `ts`) and runs `refresh` in the background; if a
 * refresh is already in flight it just polls in the background. Returns
 * immediately either way — the caller then serves whatever the store currently
 * holds (stale-while-revalidate).
 *
 * `refresh` must fetch upstream and write the data store(s); it must NOT touch
 * this gate's counters — that's handled here once it resolves.
 *
 * Outside the "live" season phase (closed/rollover — see seasonPhase.ts) this
 * is a pure no-op: no upstream call, ever, regardless of TTL. The caller then
 * just serves whatever's already in its data store, unchanged. This is the
 * single choke point for that — fixtures/scores/standings routes all call
 * this and need no phase-awareness of their own.
 */
export async function withFreshness(
  kv: KVNamespace,
  keys: GateKeys,
  ttlMs: number,
  refresh: () => Promise<unknown>,
  ctx: BackgroundCtx,
): Promise<void> {
  if ((await getSeasonPhase(kv)) !== "live") return;

  const [callStr, refreshStr, tsStr] = await Promise.all([
    kv.get(keys.call),
    kv.get(keys.refresh),
    kv.get(keys.ts),
  ]);

  const call = parseInt0(callStr);
  const refresh_ = parseInt0(refreshStr);
  const ts = tsStr ? new Date(tsStr).getTime() : 0;
  const stale = Date.now() - ts >= ttlMs;

  if (call === refresh_ && stale) {
    // This Worker claims the refresh — bump call, then refresh in background.
    // (Residual race per spec §10.2: two Workers can both claim; worst case is
    // one duplicate upstream call. Correctness is unaffected.)
    await kv.put(keys.call, String(call + 1));
    await kv.put(keys.ts, new Date().toISOString());
    ctx.waitUntil(runRefresh(kv, keys, call + 1, refresh));
  } else if (call > refresh_) {
    // Refresh already in flight elsewhere — background housekeeping only.
    ctx.waitUntil(pollUntilFresh(kv, keys, call));
  }
  // call === refresh && !stale -> store fresh, serve directly.
}

async function runRefresh(
  kv: KVNamespace,
  keys: GateKeys,
  expectedCall: number,
  refresh: () => Promise<unknown>,
): Promise<void> {
  try {
    await refresh();
    await kv.put(keys.refresh, String(expectedCall));
  } catch (err) {
    // Leave refresh < call so a later request retries. Stale data already served.
    console.error(JSON.stringify({ msg: "refresh failed", key: keys.call, error: String(err) }));
  }
}

async function pollUntilFresh(kv: KVNamespace, keys: GateKeys, expectedCall: number): Promise<void> {
  for (let i = 0; i < MAX_RETRIES; i++) {
    await sleep(1000);
    const refresh = parseInt0(await kv.get(keys.refresh));
    if (refresh >= expectedCall) return; // fresh — next user request gets it
  }
  // Timed out — stale was already served, next request will retry.
}

/**
 * Mark a gate fresh without claiming a refresh. Used to co-warm a *sibling* gate
 * after a shared upstream fetch has already written its data store — e.g. a
 * /matches fetch warms both scores and fixtures, so whichever gate triggered it,
 * the other is touched so it won't re-fetch the same upstream inside its window.
 */
export async function touchGate(kv: KVNamespace, keys: GateKeys): Promise<void> {
  const call = parseInt0(await kv.get(keys.call));
  await kv.put(keys.refresh, String(call));
  await kv.put(keys.ts, new Date().toISOString());
}

/**
 * Reset a gate to a fresh, settled (0,0) state. Called by the nightly cron after
 * it has written the store, so the first user of the day gets fresh data with
 * zero upstream calls and no accumulated integer drift (§10.3).
 */
export async function resetGate(kv: KVNamespace, keys: GateKeys): Promise<void> {
  await kv.put(keys.call, "0");
  await kv.put(keys.refresh, "0");
  await kv.put(keys.ts, new Date().toISOString());
}
