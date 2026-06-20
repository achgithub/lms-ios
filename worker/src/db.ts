// D1 access — read queries for the API, write/upsert helpers for the cron sync.
// Only provider-sourced data lives here (teams, fixtures, standings).

import type { Fixture, FixtureStatus, MatchWinner, Standing, Team } from "./types";

// ── Row shapes as stored in D1 ──────────────────────────────────────────────
interface TeamRow {
  id: string;
  external_id: number;
  name: string;
  short_name: string | null;
  tla: string | null;
  league_id: string;
}
interface FixtureRow {
  id: number;
  matchday: number | null;
  kickoff: string;
  status: string;
  home_team_id: number;
  away_team_id: number;
  home_score: number | null;
  away_score: number | null;
  winner: string | null;
  updated_at: string;
}
interface StandingRow {
  team_id: number;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
  goal_difference: number;
  points: number;
  updated_at: string;
}

function toTeam(r: TeamRow): Team {
  return {
    id: r.id,
    externalId: r.external_id,
    name: r.name,
    shortName: r.short_name,
    tla: r.tla,
    leagueId: r.league_id,
  };
}
function toFixture(r: FixtureRow): Fixture {
  return {
    id: r.id,
    matchday: r.matchday,
    kickoff: r.kickoff,
    status: r.status as FixtureStatus,
    homeTeamId: r.home_team_id,
    awayTeamId: r.away_team_id,
    homeScore: r.home_score,
    awayScore: r.away_score,
    winner: r.winner as MatchWinner,
    updatedAt: r.updated_at,
  };
}
function toStanding(r: StandingRow): Standing {
  return {
    teamId: r.team_id,
    position: r.position,
    played: r.played,
    won: r.won,
    drawn: r.drawn,
    lost: r.lost,
    goalsFor: r.goals_for,
    goalsAgainst: r.goals_against,
    goalDifference: r.goal_difference,
    points: r.points,
    updatedAt: r.updated_at,
  };
}

// ── Reads (API) ─────────────────────────────────────────────────────────────

export interface FixtureQuery {
  dateFrom?: string; // ISO8601 inclusive
  dateTo?: string; // ISO8601 inclusive
  matchday?: number;
}

export async function getFixtures(db: D1Database, q: FixtureQuery = {}): Promise<Fixture[]> {
  const where: string[] = [];
  const binds: unknown[] = [];
  if (q.dateFrom) {
    where.push("kickoff >= ?");
    binds.push(q.dateFrom);
  }
  if (q.dateTo) {
    where.push("kickoff <= ?");
    binds.push(q.dateTo);
  }
  if (q.matchday !== undefined) {
    where.push("matchday = ?");
    binds.push(q.matchday);
  }
  const sql =
    "SELECT * FROM fixtures" +
    (where.length ? ` WHERE ${where.join(" AND ")}` : "") +
    " ORDER BY kickoff ASC";
  const { results } = await db
    .prepare(sql)
    .bind(...binds)
    .all<FixtureRow>();
  return results.map(toFixture);
}

export async function getStandings(db: D1Database): Promise<Standing[]> {
  const { results } = await db
    .prepare("SELECT * FROM standings ORDER BY position ASC")
    .all<StandingRow>();
  return results.map(toStanding);
}

export async function getTeams(db: D1Database): Promise<Team[]> {
  const { results } = await db
    .prepare("SELECT * FROM teams ORDER BY name ASC")
    .all<TeamRow>();
  return results.map(toTeam);
}

// ── Writes (cron sync) ──────────────────────────────────────────────────────

// Upserts the provider's current team list, then prunes any team no longer
// referenced by a fixture or standings row. We deliberately keep ~2 seasons
// of fixtures cached at once (current + next), so a team can legitimately
// outlive its season in this table (e.g. a just-relegated club's last-season
// results still need its name) — pruning by "not in the latest /teams fetch"
// would delete those and either violate the fixtures/standings FK on
// teams.external_id or orphan historical fixture display ("Team 1076"
// instead of "Coventry City"). Pruning by "not referenced anywhere" is safe
// and self-heals once those old fixtures eventually age out.
export async function upsertTeams(db: D1Database, teams: Team[]): Promise<void> {
  if (teams.length === 0) return;
  const stmt = db.prepare(
    `INSERT INTO teams (id, external_id, name, short_name, tla, league_id)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(external_id) DO UPDATE SET
       name = excluded.name, short_name = excluded.short_name,
       tla = excluded.tla, league_id = excluded.league_id`,
  );
  const prune = db.prepare(
    `DELETE FROM teams WHERE external_id NOT IN (
       SELECT home_team_id FROM fixtures UNION SELECT away_team_id FROM fixtures
       UNION SELECT team_id FROM standings
     )`,
  );
  await db.batch([
    ...teams.map((t) => stmt.bind(t.id, t.externalId, t.name, t.shortName, t.tla, t.leagueId)),
    prune,
  ]);
}

export async function upsertFixtures(db: D1Database, fixtures: Fixture[]): Promise<void> {
  if (fixtures.length === 0) return;
  const stmt = db.prepare(
    `INSERT INTO fixtures
       (id, matchday, kickoff, status, home_team_id, away_team_id,
        home_score, away_score, winner, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       matchday = excluded.matchday, kickoff = excluded.kickoff,
       status = excluded.status, home_score = excluded.home_score,
       away_score = excluded.away_score, winner = excluded.winner,
       updated_at = excluded.updated_at`,
  );
  await db.batch(
    fixtures.map((f) =>
      stmt.bind(
        f.id, f.matchday, f.kickoff, f.status, f.homeTeamId, f.awayTeamId,
        f.homeScore, f.awayScore, f.winner, f.updatedAt,
      ),
    ),
  );
}

export async function replaceStandings(db: D1Database, standings: Standing[]): Promise<void> {
  if (standings.length === 0) return;
  const insert = db.prepare(
    `INSERT INTO standings
       (team_id, position, played, won, drawn, lost,
        goals_for, goals_against, goal_difference, points, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(team_id) DO UPDATE SET
       position = excluded.position, played = excluded.played,
       won = excluded.won, drawn = excluded.drawn, lost = excluded.lost,
       goals_for = excluded.goals_for, goals_against = excluded.goals_against,
       goal_difference = excluded.goal_difference, points = excluded.points,
       updated_at = excluded.updated_at`,
  );
  await db.batch(
    standings.map((s) =>
      insert.bind(
        s.teamId, s.position, s.played, s.won, s.drawn, s.lost,
        s.goalsFor, s.goalsAgainst, s.goalDifference, s.points, s.updatedAt,
      ),
    ),
  );
}

export async function recordSync(
  db: D1Database,
  dataset: "fixtures" | "standings" | "teams",
  rowCount: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO sync_meta (dataset, synced_at, row_count)
       VALUES (?, ?, ?)
       ON CONFLICT(dataset) DO UPDATE SET
         synced_at = excluded.synced_at, row_count = excluded.row_count`,
    )
    .bind(dataset, new Date().toISOString(), rowCount)
    .run();
}
