// Nightly maintenance + on-demand seeding (spec §10.3).
// Teams have no request-triggered gate (they change at most seasonally), so the
// cron is their only refresh path. Matches (scores+fixtures) and standings DO
// have request-triggered gates (see refresh.ts / the routes) which cover the
// rest of the day; the cron's extra job for them is to warm the stores and reset
// the gates to a clean (0,0) state for the day's first user.

import { recordSync, upsertTeams } from "./db";
import type { Provider } from "./football";
import { FIXTURES_KEYS, resetGate, SCORES_KEYS, STANDINGS_KEYS } from "./gate";
import { refreshMatchData, refreshStandings } from "./refresh";
import { getSeasonPhase } from "./seasonPhase";

export async function syncTeams(db: D1Database, provider: Provider, season?: number): Promise<number> {
  const teams = await provider.fetchTeams(season);
  await upsertTeams(db, teams);
  await recordSync(db, "teams", teams.length);
  return teams.length;
}

// Full nightly maintenance, run by the single per-league cron (see wrangler.jsonc).
// The Workers free plan caps cron triggers at 5 per account, so each league gets
// one daily trigger that runs the whole sequence rather than split jobs. Order:
// teams first (fixtures + standings reference them), then matches and standings.
// All of this runs in the league's maintenance window (the dead zone), so the
// serial upstream calls are free of contention and well within the rate limit.
export async function runMaintenance(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
): Promise<void> {
  // Outside "live" (closed/rollover — see seasonPhase.ts), there is nothing to
  // learn from the upstream and no point spending the call: a manager has
  // either deliberately frozen the close-season cache or is mid-rollover with
  // a one-off admin sync already covering it. Skip entirely; don't even reset
  // the gates (nothing was refreshed for them to be settled against).
  if ((await getSeasonPhase(kv)) !== "live") {
    console.log(JSON.stringify({ msg: "cron skipped — season phase not live" }));
    return;
  }

  const teams = await syncTeams(db, provider);
  const { scores, fixtures } = await refreshMatchData(db, kv, provider);
  const standings = await refreshStandings(db, provider);
  // Reset every gate to a settled (0,0)+now state: fresh for the day's first
  // user, no accumulated integer drift. This overrides the touch refreshMatchData
  // just applied — intentional; the nightly window is the clean-slate point.
  await Promise.all([
    resetGate(kv, SCORES_KEYS),
    resetGate(kv, FIXTURES_KEYS),
    resetGate(kv, STANDINGS_KEYS),
  ]);
  console.log(
    JSON.stringify({ msg: "cron maintenance", teams, fixtures, standings, scores }),
  );
}
