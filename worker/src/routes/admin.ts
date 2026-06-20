import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { FootballDataProvider } from "../football";
import { refreshMatchData, refreshStandings } from "../refresh";
import { getSeasonPhase, setSeasonPhase, type SeasonPhase } from "../seasonPhase";
import { syncTeams } from "../sync";
import { getLeagueConfig } from "../types";

// Admin endpoint to trigger a provider sync on demand (ops / first seed),
// instead of waiting for the maintenance-window cron. Guarded by ADMIN_TOKEN.
//
//   POST /admin/sync?what=all|teams|fixtures|standings|scores&season=YYYY
//   Authorization: Bearer <ADMIN_TOKEN>
//
// `season` (optional) pins the upstream call to a specific season (the year it
// starts, e.g. 2026 for "2026/27") instead of football-data.org's default
// "current season" pointer — for deliberately pulling in next season's data
// during a rollover, ahead of/independent from that pointer flipping. Omit it
// for normal operation (today's behaviour, unchanged).
//
// Note: scores + fixtures share one upstream (/matches), so what=fixtures and
// what=scores both run the single combined match refresh (and report both counts).
//
// Safe to remove post-launch — the cron (§10.3) covers normal operation.
export const admin = new Hono<{ Bindings: Env }>();

admin.post("/sync", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : undefined;

  const what = c.req.query("what") ?? "all";
  const synced: Record<string, number> = {};
  // Teams first (fixtures + standings reference them).
  if (what === "all" || what === "teams") synced.teams = await syncTeams(c.env.DB, provider, season);
  if (what === "all" || what === "fixtures" || what === "scores") {
    const m = await refreshMatchData(c.env.DB, c.env.SCORES, provider, season);
    synced.fixtures = m.fixtures;
    synced.scores = m.scores;
  }
  if (what === "all" || what === "standings") {
    synced.standings = await refreshStandings(c.env.DB, provider, season);
  }

  return c.json({ ok: true, synced });
});

// Read-only diagnostic: calls the upstream /standings endpoint for a given
// season WITHOUT writing anything to D1 — for checking whether a not-yet-
// started season returns an empty table or still falls back to a previous
// one, before deciding to run a real (destructive, replaces D1) sync.
//
//   GET /admin/probe-standings?season=YYYY
//   Authorization: Bearer <ADMIN_TOKEN>
admin.get("/probe-standings", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const seasonParam = c.req.query("season");
  const season = seasonParam ? parseInt(seasonParam, 10) : undefined;
  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  try {
    const standings = await provider.fetchStandings(season);
    return c.json({ ok: true, season, rowCount: standings.length, rows: standings });
  } catch (err) {
    return c.json({ ok: false, season, error: String(err) }, 502);
  }
});

// Season-lifecycle phase (live | closed | rollover — see seasonPhase.ts).
// Curl fallback for the dashboard's buttons (worker-dash writes the same KV
// key directly, since it's already bound there); kept here too so this is
// controllable without dashboard access, and documented in one place.
//
//   GET  /admin/phase
//   POST /admin/phase?value=live|closed|rollover
//   Authorization: Bearer <ADMIN_TOKEN>
admin.get("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  return c.json({ phase: await getSeasonPhase(c.env.SCORES) });
});

admin.post("/phase", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const value = c.req.query("value");
  if (value !== "live" && value !== "closed" && value !== "rollover") {
    return c.json({ error: "value must be live|closed|rollover" }, 400);
  }
  await setSeasonPhase(c.env.SCORES, value as SeasonPhase);
  return c.json({ ok: true, phase: value });
});
