// Upstream → store refreshers, shared by the request-triggered gates (routes),
// the on-demand admin sync, and the nightly cron. Each fetches the provider once
// and writes the relevant store(s); the gate counters are managed by gate.ts.

import { recordSync, replaceStandings, upsertFixtures } from "./db";
import type { Provider } from "./football";
import { FIXTURES_KEYS, SCORES_DATA_KEY, SCORES_KEYS, touchGate } from "./gate";

export interface MatchCounts {
  scores: number;
  fixtures: number;
}

/**
 * Fetch /matches once → cache the compact scores in KV, store the full fixtures
 * in D1, then mark BOTH the scores and fixtures gates fresh. Scores and fixtures
 * share this one upstream source, so a scores refresh co-warms fixtures and a
 * fixtures refresh co-warms scores ("one /matches → both timestamps", spec
 * cross-resource warming). The caller's own gate is settled by gate.ts on top of
 * this — the touch here is what keeps the *sibling* gate from re-fetching.
 */
export async function refreshMatchData(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
  season?: number,
): Promise<MatchCounts> {
  const { scores, fixtures } = await provider.fetchMatchData(season);
  await upsertFixtures(db, fixtures);
  await recordSync(db, "fixtures", fixtures.length);
  await kv.put(SCORES_DATA_KEY, JSON.stringify(scores));
  await Promise.all([touchGate(kv, SCORES_KEYS), touchGate(kv, FIXTURES_KEYS)]);
  return { scores: scores.length, fixtures: fixtures.length };
}

/**
 * Fetch the league table → replace it in D1. Standings have their own upstream
 * (/standings) and their own gate; nothing co-warms them.
 */
export async function refreshStandings(db: D1Database, provider: Provider, season?: number): Promise<number> {
  const standings = await provider.fetchStandings(season);
  await replaceStandings(db, standings);
  await recordSync(db, "standings", standings.length);
  return standings.length;
}
