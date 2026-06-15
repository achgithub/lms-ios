// Cron-driven sync of provider data into D1 + KV (spec §10.3).
// All of this runs inside the league's maintenance window (the dead zone with
// no matches and no users). Demand-driven score caching (scores.ts) handles the
// rest of the day.

import { recordSync, replaceStandings, upsertFixtures, upsertTeams } from "./db";
import type { Provider } from "./football";
import { warmCache } from "./scores";

export async function syncTeams(db: D1Database, provider: Provider): Promise<number> {
  const teams = await provider.fetchTeams();
  await upsertTeams(db, teams);
  await recordSync(db, "teams", teams.length);
  return teams.length;
}

export async function syncFixtures(db: D1Database, provider: Provider): Promise<number> {
  const fixtures = await provider.fetchFixtures();
  await upsertFixtures(db, fixtures);
  await recordSync(db, "fixtures", fixtures.length);
  return fixtures.length;
}

export async function syncStandings(db: D1Database, provider: Provider): Promise<number> {
  const standings = await provider.fetchStandings();
  await replaceStandings(db, standings);
  await recordSync(db, "standings", standings.length);
  return standings.length;
}

// Cache-warm: fetch once, write the shared cache, reset the counter pair to (0,0).
export async function warmScores(kv: KVNamespace, provider: Provider): Promise<number> {
  const scores = await provider.fetchScores();
  await warmCache(kv, scores);
  return scores.length;
}

// Full nightly maintenance, run by the single per-league cron (see wrangler.jsonc).
// The Workers free plan caps cron triggers at 5 per account, so each league gets
// one daily trigger that runs the whole sequence rather than three split jobs.
// Order matters: teams first (fixtures + standings reference them), then fixtures,
// standings, and finally the score-cache warm. All of this runs in the league's
// maintenance window (the dead zone), so the extra serial calls are free of
// contention and well within the provider's rate limit.
export async function runMaintenance(
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
): Promise<void> {
  const t = await syncTeams(db, provider);
  const f = await syncFixtures(db, provider);
  const s = await syncStandings(db, provider);
  const n = await warmScores(kv, provider);
  console.log(
    JSON.stringify({ msg: "cron maintenance", teams: t, fixtures: f, standings: s, scores: n }),
  );
}
