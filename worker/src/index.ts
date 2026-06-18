// LMS Worker — generic, league-agnostic read-only sports-data API.
// One deployment (wrangler env) per league; all league specifics come from
// per-env config (see types.ts / wrangler.jsonc). Game state lives on the app.

import { Hono } from "hono";
import { getDemoClock } from "./demo";
import { FootballDataProvider } from "./football";
// import { requireAttestation } from "./middleware/attest"; // see TODO below
import { admin } from "./routes/admin";
import { attest } from "./routes/attest";
import { demo } from "./routes/demo";
import { fixtures } from "./routes/fixtures";
import { scores } from "./routes/scores";
import { standings } from "./routes/standings";
import { teams } from "./routes/teams";
import { runMaintenance } from "./sync";
import { getLeagueConfig } from "./types";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "lms-worker", league: c.env.LEAGUE_ID }));

app.get("/health", async (c) => {
  const { results } = await c.env.DB.prepare(
    "SELECT dataset, synced_at, row_count FROM sync_meta",
  ).all<{ dataset: string; synced_at: string; row_count: number }>();
  const demoClock = await getDemoClock(c.env.SCORES);
  return c.json({ ok: true, league: c.env.LEAGUE_ID, sync: results, demo: demoClock });
});

// App Attest enrolment (public) — must mount BEFORE the guarded data routes.
app.route("/attest", attest);

// Data routes — guarded by App Attest so only the genuine iOS app can reach the
// licensed feed. /health and /admin (own ADMIN_TOKEN) are intentionally not guarded.
// TEMPORARILY DISABLED (2026-06-18): go-live sequence (Developer-portal capability,
// ATTEST_CHALLENGE_KEY secret, attest_devices schema, app re-registration) is not
// complete yet — see docs/app-attest-status.md. Re-enable these 8 lines as step 4 of
// that sequence, not before.
// app.use("/fixtures/*", requireAttestation);
// app.use("/scores/*", requireAttestation);
// app.use("/standings/*", requireAttestation);
// app.use("/teams/*", requireAttestation);
// app.use("/fixtures", requireAttestation);
// app.use("/scores", requireAttestation);
// app.use("/standings", requireAttestation);
// app.use("/teams", requireAttestation);

app.route("/fixtures", fixtures);
app.route("/scores", scores);
app.route("/standings", standings);
app.route("/teams", teams);
app.route("/admin/demo", demo);
app.route("/admin", admin);

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error(JSON.stringify({ msg: "unhandled error", error: String(err) }));
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,

  // Single nightly maintenance cron per league (spec §10.3). One trigger per env
  // keeps us under the Workers free-plan cap of 5 cron triggers per account.
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    const cfg = getLeagueConfig(env);
    const provider = new FootballDataProvider(
      env.FOOTBALL_DATA_TOKEN,
      cfg.footballDataCode,
      cfg.leagueId,
    );
    ctx.waitUntil(runMaintenance(env.DB, env.SCORES, provider));
  },
} satisfies ExportedHandler<Env>;
