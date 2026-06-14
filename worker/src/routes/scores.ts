import { Hono } from "hono";
import { getFixtures } from "../db";
import { demoScores, getDemoClock } from "../demo";
import { FootballDataProvider } from "../football";
import { getScores } from "../scores";
import { getLeagueConfig } from "../types";

// GET /scores
// One shared cache for everyone — free vs subscriber is not a freshness tier;
// the app gates the refresh action behind a rewarded ad for free users. Stale
// data is served immediately and refreshed in the background (spec §10.2).
// When a demo clock is set, returns the current matchday's (synthetic) scores.
export const scores = new Hono<{ Bindings: Env }>();

scores.get("/", async (c) => {
  const clock = await getDemoClock(c.env.SCORES);
  if (clock) {
    return c.json(demoScores(await getFixtures(c.env.DB), clock));
  }

  const cfg = getLeagueConfig(c.env);
  const provider = new FootballDataProvider(
    c.env.FOOTBALL_DATA_TOKEN,
    cfg.footballDataCode,
    cfg.leagueId,
  );
  const data = await getScores(
    c.env.SCORES,
    cfg.scoreTtlMs,
    () => provider.fetchScores(),
    c.executionCtx,
  );
  return c.json(data);
});
