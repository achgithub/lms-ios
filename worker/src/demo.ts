// Demo clock — present the stored (completed) season as if it were mid-season,
// so the app can be tested through a realistic timeline (open a round → live →
// results → close → next week). Non-destructive: the real data in D1 is never
// changed; these are per-request transforms gated on a clock stored in KV.
//
// Clock = { matchday, phase }, phase advancing scheduled → live → finished, then
// rolling to the next matchday. Absent clock = normal mode (real data served).

import type { Fixture, ScoreEntry, Standing, Team } from "./types";

export type DemoPhase = "scheduled" | "live" | "finished";
export interface DemoClock {
  matchday: number;
  phase: DemoPhase;
}

const CLOCK_KEY = "demo:clock";
const DAY = 86_400_000;
const HOUR = 3_600_000;
export const PHASES: DemoPhase[] = ["scheduled", "live", "finished"];

// The real football-data.org feed has no fractional seconds (e.g.
// "2024-08-17T11:30:00Z"); the app's ISO8601DateFormatter is configured to
// match that and silently fails to parse Date#toISOString()'s milliseconds.
// Strip them so demo timestamps parse the same as real ones.
function isoNoMs(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export async function getDemoClock(kv: KVNamespace): Promise<DemoClock | null> {
  const raw = await kv.get(CLOCK_KEY);
  if (!raw) return null;
  try {
    const c = JSON.parse(raw) as DemoClock;
    if (typeof c.matchday === "number" && PHASES.includes(c.phase)) return c;
  } catch {
    /* malformed — treat as no clock */
  }
  return null;
}

export async function setDemoClock(kv: KVNamespace, clock: DemoClock): Promise<void> {
  await kv.put(CLOCK_KEY, JSON.stringify(clock));
}

export async function clearDemoClock(kv: KVNamespace): Promise<void> {
  await kv.delete(CLOCK_KEY);
}

/** Step the clock: scheduled → live → finished, then roll to next matchday (capped). */
export function advanceClock(clock: DemoClock, maxMatchday: number): DemoClock {
  const nextPhase = PHASES[PHASES.indexOf(clock.phase) + 1];
  if (nextPhase) return { matchday: clock.matchday, phase: nextPhase };
  if (clock.matchday >= maxMatchday) return clock; // season complete — stay put
  return { matchday: clock.matchday + 1, phase: "scheduled" };
}

/**
 * Re-time and re-status the real (completed) season as of the demo clock:
 * - matchdays before the current one  → FINISHED with their real scores,
 * - the current matchday              → SCHEDULED / IN_PLAY / FINISHED per phase,
 * - matchdays after the current one   → SCHEDULED in the near future.
 * Kickoffs are spaced ~weekly around "now" so deadlines/round-opening make sense.
 */
export function applyDemoToFixtures(fixtures: Fixture[], clock: DemoClock, now = Date.now()): Fixture[] {
  const nowISO = isoNoMs(now);
  const weekly = (offsetDays: number) => isoNoMs(now + offsetDays * DAY);

  return fixtures.map((f): Fixture => {
    const md = f.matchday ?? 0;
    if (md < clock.matchday) {
      return { ...f, status: "FINISHED", kickoff: weekly((md - clock.matchday) * 7), updatedAt: nowISO };
    }
    if (md > clock.matchday) {
      return {
        ...f, status: "TIMED", kickoff: weekly((md - clock.matchday) * 7),
        homeScore: null, awayScore: null, winner: null, updatedAt: nowISO,
      };
    }
    switch (clock.phase) {
      case "scheduled":
        return {
          ...f, status: "TIMED", kickoff: isoNoMs(now + 2 * DAY),
          homeScore: null, awayScore: null, winner: null, updatedAt: nowISO,
        };
      case "live":
        // Real scores shown as the "current" live score; winner undecided.
        return { ...f, status: "IN_PLAY", kickoff: isoNoMs(now - HOUR), winner: null, updatedAt: nowISO };
      case "finished":
      default:
        return { ...f, status: "FINISHED", kickoff: isoNoMs(now - DAY), updatedAt: nowISO };
    }
  });
}

/** Scores payload (GET /scores) in demo mode: the current matchday's fixtures. */
export function demoScores(fixtures: Fixture[], clock: DemoClock, now = Date.now()): ScoreEntry[] {
  return applyDemoToFixtures(fixtures, clock, now)
    .filter((f) => f.matchday === clock.matchday)
    .map((f): ScoreEntry => ({
      id: f.id,
      status: f.status,
      minute: f.status === "IN_PLAY" ? 60 : null,
      homeTeamId: f.homeTeamId,
      awayTeamId: f.awayTeamId,
      homeScore: f.homeScore,
      awayScore: f.awayScore,
      winner: f.winner,
    }));
}

/** League table computed from results up to the demo clock (mid-season realistic). */
export function demoStandings(fixtures: Fixture[], teams: Team[], clock: DemoClock, now = Date.now()): Standing[] {
  const counted = fixtures.filter((f) => {
    const md = f.matchday ?? 0;
    if (md < clock.matchday) return true;
    return md === clock.matchday && clock.phase === "finished";
  });

  const nowISO = isoNoMs(now);
  const table = new Map<number, Standing>();
  const ensure = (id: number): Standing => {
    let row = table.get(id);
    if (!row) {
      row = {
        teamId: id, position: 0, played: 0, won: 0, drawn: 0, lost: 0,
        goalsFor: 0, goalsAgainst: 0, goalDifference: 0, points: 0, updatedAt: nowISO,
      };
      table.set(id, row);
    }
    return row;
  };
  for (const t of teams) ensure(t.externalId);

  for (const f of counted) {
    if (f.homeScore == null || f.awayScore == null) continue;
    const h = ensure(f.homeTeamId);
    const a = ensure(f.awayTeamId);
    h.played++; a.played++;
    h.goalsFor += f.homeScore; h.goalsAgainst += f.awayScore;
    a.goalsFor += f.awayScore; a.goalsAgainst += f.homeScore;
    if (f.homeScore > f.awayScore) { h.won++; h.points += 3; a.lost++; }
    else if (f.homeScore < f.awayScore) { a.won++; a.points += 3; h.lost++; }
    else { h.drawn++; a.drawn++; h.points++; a.points++; }
  }

  const rows = [...table.values()];
  for (const r of rows) r.goalDifference = r.goalsFor - r.goalsAgainst;
  rows.sort((x, y) =>
    y.points - x.points ||
    y.goalDifference - x.goalDifference ||
    y.goalsFor - x.goalsFor ||
    x.teamId - y.teamId,
  );
  rows.forEach((r, i) => { r.position = i + 1; });
  return rows;
}
