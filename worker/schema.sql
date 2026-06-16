-- LMS Worker — D1 schema (per-league instance, e.g. lms-pl-db)
--
-- Scope: this Worker is a READ-ONLY sports-data API. It stores ONLY data
-- sourced from the upstream provider (football-data.org). All game state
-- (games, players, rounds, picks) lives on the app, not here.
--
-- Apply: wrangler d1 execute lms-pl-db --env pl --remote --file=./schema.sql

PRAGMA foreign_keys = ON;

-- ── Teams ────────────────────────────────────────────────────────────────
-- One row per club in this league. `external_id` is the provider's team id.
-- Only text data is stored — the app renders bespoke colour tiles (§15), so the
-- provider's crest/logo image URL is deliberately NOT persisted or served.
CREATE TABLE IF NOT EXISTS teams (
  id          TEXT PRIMARY KEY,           -- internal/stable id (provider id as text)
  external_id INTEGER NOT NULL UNIQUE,    -- football-data.org team id
  name        TEXT NOT NULL,
  short_name  TEXT,                       -- e.g. "Arsenal"
  tla         TEXT,                       -- provider 3-letter code, e.g. "ARS"
  league_id   TEXT NOT NULL               -- LEAGUE_ID this Worker serves (e.g. "PL")
);

CREATE INDEX IF NOT EXISTS idx_teams_external ON teams (external_id);

-- ── Fixtures ───────────────────────────────────────────────────────────────
-- Live/recent fixtures synced from the provider. `id` is the provider match id.
CREATE TABLE IF NOT EXISTS fixtures (
  id           INTEGER PRIMARY KEY,        -- football-data.org match id
  matchday     INTEGER,                    -- league matchday / round number
  kickoff      TEXT NOT NULL,              -- ISO8601, always UTC
  status       TEXT NOT NULL,              -- SCHEDULED | TIMED | IN_PLAY | PAUSED | FINISHED | POSTPONED | SUSPENDED | CANCELLED
  home_team_id INTEGER NOT NULL,
  away_team_id INTEGER NOT NULL,
  home_score   INTEGER,                    -- null until played
  away_score   INTEGER,                    -- null until played
  winner       TEXT,                       -- HOME_TEAM | AWAY_TEAM | DRAW | null
  updated_at   TEXT NOT NULL,              -- ISO8601 UTC, last sync write
  FOREIGN KEY (home_team_id) REFERENCES teams (external_id),
  FOREIGN KEY (away_team_id) REFERENCES teams (external_id)
);

CREATE INDEX IF NOT EXISTS idx_fixtures_kickoff  ON fixtures (kickoff);
CREATE INDEX IF NOT EXISTS idx_fixtures_matchday ON fixtures (matchday);
CREATE INDEX IF NOT EXISTS idx_fixtures_status   ON fixtures (status);

-- ── Standings ───────────────────────────────────────────────────────────────
-- League table, one row per team. Refreshed by the standings cron (Mon & Thu).
CREATE TABLE IF NOT EXISTS standings (
  team_id    INTEGER PRIMARY KEY,          -- provider team id
  position   INTEGER NOT NULL,
  played     INTEGER NOT NULL DEFAULT 0,
  won        INTEGER NOT NULL DEFAULT 0,
  drawn      INTEGER NOT NULL DEFAULT 0,
  lost       INTEGER NOT NULL DEFAULT 0,
  goals_for     INTEGER NOT NULL DEFAULT 0,
  goals_against INTEGER NOT NULL DEFAULT 0,
  goal_difference INTEGER NOT NULL DEFAULT 0,
  points     INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,                -- ISO8601 UTC
  FOREIGN KEY (team_id) REFERENCES teams (external_id)
);

CREATE INDEX IF NOT EXISTS idx_standings_position ON standings (position);

-- ── Sync metadata ───────────────────────────────────────────────────────────
-- Records the last successful upstream sync per dataset, for observability and
-- so reads can report freshness. Not strictly required but cheap and useful.
CREATE TABLE IF NOT EXISTS sync_meta (
  dataset    TEXT PRIMARY KEY,             -- 'fixtures' | 'standings' | 'teams'
  synced_at  TEXT NOT NULL,               -- ISO8601 UTC
  row_count  INTEGER NOT NULL DEFAULT 0
);
