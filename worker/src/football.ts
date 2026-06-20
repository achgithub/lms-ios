// Upstream data provider. football-data.org is the first implementation of a
// generic Provider interface (spec §17.3) — other sports/countries supply their
// own provider later; the engine only depends on the normalised shapes below.

import type {
  Fixture,
  FixtureStatus,
  MatchWinner,
  ScoreEntry,
  Standing,
  Team,
} from "./types";

export interface Provider {
  // `season` (the year a season starts, e.g. 2026 for "2026/27") pins the
  // upstream call to a specific season instead of football-data.org's default
  // "current season" pointer for the competition — which only flips once that
  // pointer is updated upstream, not necessarily when fixtures for the next
  // season are published. Omitted on the normal live path (today's behaviour,
  // unpinned); only used by the admin one-off sync during a season rollover.
  fetchTeams(season?: number): Promise<Team[]>;
  // Scores and fixtures share one upstream source (/matches), so one fetch
  // projects into both shapes — see fetchMatchData. This keeps a scores refresh
  // and a fixtures refresh from each making their own redundant /matches call.
  fetchMatchData(season?: number): Promise<MatchData>;
  fetchStandings(season?: number): Promise<Standing[]>;
}

// One /matches response projected into the two shapes the app consumes:
// compact scores (cached in KV) and full fixtures (stored in D1).
export interface MatchData {
  scores: ScoreEntry[];
  fixtures: Fixture[];
}

const BASE = "https://api.football-data.org/v4";

// ── football-data.org wire types (only the fields we consume) ────────────────
interface FDTeam {
  id: number;
  name: string;
  shortName?: string | null;
  tla?: string | null;
}
interface FDMatch {
  id: number;
  utcDate: string;
  status: string;
  matchday: number | null;
  minute?: number | null;
  homeTeam: { id: number };
  awayTeam: { id: number };
  score: { winner: MatchWinner; fullTime: { home: number | null; away: number | null } };
}
interface FDTableRow {
  position: number;
  team: { id: number };
  playedGames: number;
  won: number;
  draw: number;
  lost: number;
  points: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
}

const KNOWN_STATUSES: ReadonlySet<string> = new Set([
  "SCHEDULED", "TIMED", "IN_PLAY", "PAUSED", "FINISHED", "POSTPONED", "SUSPENDED", "CANCELLED",
]);

function normaliseStatus(s: string): FixtureStatus {
  return (KNOWN_STATUSES.has(s) ? s : "SCHEDULED") as FixtureStatus;
}

export class FootballDataProvider implements Provider {
  constructor(
    private readonly token: string,
    private readonly competitionCode: string,
    private readonly leagueId: string,
  ) {}

  private async get<T>(path: string, season?: number): Promise<T> {
    const url = season ? `${BASE}${path}?season=${season}` : `${BASE}${path}`;
    const res = await fetch(url, {
      headers: { "X-Auth-Token": this.token },
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`football-data ${path} -> ${res.status}: ${body.slice(0, 300)}`);
    }
    return (await res.json()) as T;
  }

  async fetchTeams(season?: number): Promise<Team[]> {
    const data = await this.get<{ teams: FDTeam[] }>(
      `/competitions/${this.competitionCode}/teams`,
      season,
    );
    return data.teams.map((t) => ({
      id: String(t.id),
      externalId: t.id,
      name: t.name,
      shortName: t.shortName ?? null,
      tla: t.tla ?? null,
      leagueId: this.leagueId,
    }));
  }

  // One /matches fetch → both the full fixtures (D1) and the compact scores (KV).
  // Callers that only need one shape still pay a single upstream call, and the
  // shared-cache warming (scores refresh co-warms fixtures and vice versa) keys
  // off this single source.
  async fetchMatchData(season?: number): Promise<MatchData> {
    const now = new Date().toISOString();
    const data = await this.get<{ matches: FDMatch[] }>(
      `/competitions/${this.competitionCode}/matches`,
      season,
    );
    const fixtures: Fixture[] = data.matches.map((m) => ({
      id: m.id,
      matchday: m.matchday,
      kickoff: m.utcDate,
      status: normaliseStatus(m.status),
      homeTeamId: m.homeTeam.id,
      awayTeamId: m.awayTeam.id,
      homeScore: m.score.fullTime.home,
      awayScore: m.score.fullTime.away,
      winner: m.score.winner,
      updatedAt: now,
    }));
    const scores: ScoreEntry[] = data.matches.map((m) => ({
      id: m.id,
      status: normaliseStatus(m.status),
      minute: m.minute ?? null,
      homeTeamId: m.homeTeam.id,
      awayTeamId: m.awayTeam.id,
      homeScore: m.score.fullTime.home,
      awayScore: m.score.fullTime.away,
      winner: m.score.winner,
    }));
    return { scores, fixtures };
  }

  async fetchStandings(season?: number): Promise<Standing[]> {
    const now = new Date().toISOString();
    const data = await this.get<{ standings: { type: string; table: FDTableRow[] }[] }>(
      `/competitions/${this.competitionCode}/standings`,
      season,
    );
    const total = (data.standings ?? []).find((s) => s.type === "TOTAL") ?? data.standings?.[0];
    const table = total?.table ?? [];
    return table.map((r) => ({
      teamId: r.team.id,
      position: r.position,
      played: r.playedGames,
      won: r.won,
      drawn: r.draw,
      lost: r.lost,
      goalsFor: r.goalsFor,
      goalsAgainst: r.goalsAgainst,
      goalDifference: r.goalDifference,
      points: r.points,
      updatedAt: now,
    }));
  }
}
