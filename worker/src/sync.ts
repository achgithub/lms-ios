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

// Dispatch a fired cron to the right job. Cron strings must match wrangler.jsonc.
export async function runCron(
  cron: string,
  db: D1Database,
  kv: KVNamespace,
  provider: Provider,
): Promise<void> {
  switch (cron) {
    case "0 4 * * 1,4": {
      const n = await syncStandings(db, provider);
      console.log(JSON.stringify({ msg: "cron standings sync", rows: n }));
      return;
    }
    case "1 4 * * *": {
      // Teams first (fixtures reference them), then fixtures. Teams are cheap.
      const t = await syncTeams(db, provider);
      const f = await syncFixtures(db, provider);
      console.log(JSON.stringify({ msg: "cron fixtures sync", teams: t, fixtures: f }));
      return;
    }
    case "2 4 * * *": {
      const n = await warmScores(kv, provider);
      console.log(JSON.stringify({ msg: "cron score warm", entries: n }));
      return;
    }
    default:
      console.warn(JSON.stringify({ msg: "unrecognised cron", cron }));
  }
}
