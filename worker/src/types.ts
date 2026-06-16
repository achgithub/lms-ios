// Domain types for the LMS read-only sports-data API.
// All times are ISO8601 UTC strings. The app converts to local time for display.

export type FixtureStatus =
  | "SCHEDULED"
  | "TIMED"
  | "IN_PLAY"
  | "PAUSED"
  | "FINISHED"
  | "POSTPONED"
  | "SUSPENDED"
  | "CANCELLED";

export type MatchWinner = "HOME_TEAM" | "AWAY_TEAM" | "DRAW" | null;

export interface Team {
  id: string;
  externalId: number;
  name: string;
  shortName: string | null;
  tla: string | null;
  leagueId: string;
}

export interface Fixture {
  id: number;
  matchday: number | null;
  kickoff: string;
  status: FixtureStatus;
  homeTeamId: number;
  awayTeamId: number;
  homeScore: number | null;
  awayScore: number | null;
  winner: MatchWinner;
  updatedAt: string;
}

export interface Standing {
  teamId: number;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
  points: number;
  updatedAt: string;
}

// The compact score payload cached in KV and served on GET /scores.
export interface ScoreEntry {
  id: number;
  status: FixtureStatus;
  minute: number | null;
  homeTeamId: number;
  awayTeamId: number;
  homeScore: number | null;
  awayScore: number | null;
  winner: MatchWinner;
}

// League configuration, resolved from per-env wrangler vars.
// The engine is league-agnostic: every league-specific value comes from here.
export interface LeagueConfig {
  leagueId: string;
  leagueName: string;
  footballDataCode: string;
  teamsCount: number;
  roundsPerSeason: number;
  // Single shared score-cache TTL. Free vs subscriber is no longer a freshness
  // tier — everyone gets the same data; the app gates the *refresh action*
  // behind a rewarded ad for free users (see iOS AdGate). One cache = ~half the
  // upstream polling of the old two-tier split.
  scoreTtlMs: number;
  timezone: string;
  maintenanceWindowUTC: string;
}

// Parse the wrangler vars (strings) into a typed config. Numeric vars arrive as
// strings; we coerce here once so the rest of the code works with numbers.
export function getLeagueConfig(env: Env): LeagueConfig {
  const num = (v: string, name: string): number => {
    const n = Number(v);
    if (!Number.isFinite(n)) throw new Error(`Config var ${name} is not a number: ${v}`);
    return n;
  };
  return {
    leagueId: env.LEAGUE_ID,
    leagueName: env.LEAGUE_NAME,
    footballDataCode: env.FOOTBALL_DATA_CODE,
    teamsCount: num(env.TEAMS_COUNT, "TEAMS_COUNT"),
    roundsPerSeason: num(env.ROUNDS_PER_SEASON, "ROUNDS_PER_SEASON"),
    scoreTtlMs: num(env.SCORE_TTL_SECONDS, "SCORE_TTL_SECONDS") * 1000,
    timezone: env.TIMEZONE,
    maintenanceWindowUTC: env.MAINTENANCE_WINDOW_UTC,
  };
}
