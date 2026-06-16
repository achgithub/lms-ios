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
  fetchTeams(): Promise<Team[]>;
  fetchFixtures(): Promise<Fixture[]>;
  fetchStandings(): Promise<Standing[]>;
  fetchScores(): Promise<ScoreEntry[]>;
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

  private async get<T>(path: string): Promise<T> {
    const res = await fetch(`${BASE}${path}`, {
      headers: { "X-Auth-Token": this.token },
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`football-data ${path} -> ${res.status}: ${body.slice(0, 300)}`);
    }
    return (await res.json()) as T;
  }

  async fetchTeams(): Promise<Team[]> {
    const data = await this.get<{ teams: FDTeam[] }>(
      `/competitions/${this.competitionCode}/teams`,
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

  async fetchFixtures(): Promise<Fixture[]> {
    const now = new Date().toISOString();
    const data = await this.get<{ matches: FDMatch[] }>(
      `/competitions/${this.competitionCode}/matches`,
    );
    return data.matches.map((m) => ({
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
  }

  async fetchStandings(): Promise<Standing[]> {
    const now = new Date().toISOString();
    const data = await this.get<{ standings: { type: string; table: FDTableRow[] }[] }>(
      `/competitions/${this.competitionCode}/standings`,
    );
    const total = data.standings.find((s) => s.type === "TOTAL") ?? data.standings[0];
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

  // Scores reuse the matches endpoint but project to the compact KV payload.
  async fetchScores(): Promise<ScoreEntry[]> {
    const data = await this.get<{ matches: FDMatch[] }>(
      `/competitions/${this.competitionCode}/matches`,
    );
    return data.matches.map((m) => ({
      id: m.id,
      status: normaliseStatus(m.status),
      minute: m.minute ?? null,
      homeTeamId: m.homeTeam.id,
      awayTeamId: m.awayTeam.id,
      homeScore: m.score.fullTime.home,
      awayScore: m.score.fullTime.away,
      winner: m.score.winner,
    }));
  }
}
