# LMS Worker

Generic, league-agnostic **read-only sports-data API** for the LMS (Last Man
Standing) app. One Cloudflare Worker deployment per league (a wrangler *env*);
the engine never hardcodes a league — everything league-specific comes from
per-env config.

> **Scope (v1, Phase 1):** the cloud holds only provider-sourced data
> (fixtures, scores, standings from football-data.org). **All game state and
> game logic live on the app**, not here. No game tables, no auth, no push.

## Architecture

```
football-data.org ──(cron, server-side)──▶ D1 (teams, fixtures, standings)
                  ──(on-demand)──────────▶ KV score cache (counter-pair)
App ──(read only)──▶ Worker:  GET /fixtures  /scores  /standings  /teams
```

Adding a league = add a new env block in `wrangler.jsonc` (config + its own
D1/KV/cron) and a `configs/<league>/league.config.json`. No engine changes.

## Endpoints

| Method | Path                                          | Notes                              |
|--------|-----------------------------------------------|------------------------------------|
| GET    | `/fixtures?dateFrom=&dateTo=&matchday=`        | Fixtures (ISO8601 UTC), filterable |
| GET    | `/scores?tier=free\|sub`                       | KV counter-pair cache (§4.2)       |
| GET    | `/standings`                                   | League table                       |
| GET    | `/teams`                                       | Clubs (id→name resolution for app) |
| GET    | `/health`                                      | Sync freshness                     |

`/scores` tiers: `sub` ≈ 20s freshness, `free` ≈ 90 min. Trust-on-client — the
difference is freshness, not gated content (§10.2).

## Tooling (clean-machine policy)

Versions are pinned per-project so nothing proliferates globally on the host:

- **Volta** pins Node + pnpm via the `volta` field in `package.json` (auto-activates in this dir).
- **pnpm** installs into project-local `./node_modules`, hard-linked from pnpm's shared content-addressable store (one copy per version on disk).

Use `pnpm`, not `npm`. No Vite — wrangler bundles the Worker itself.

## Setup (Premier League instance)

```bash
pnpm install

# 1. Create resources, paste the returned ids into wrangler.jsonc (env.pl)
pnpm wrangler d1 create lms-pl-db
pnpm wrangler kv namespace create lms-pl-scores

# 2. Apply schema
pnpm db:apply:pl              # remote   (or db:apply:pl:local)

# 3. Provider API key (secret — never in source)
pnpm wrangler secret put FOOTBALL_DATA_TOKEN --env pl

# 4. Generate binding types, typecheck, run
pnpm types
pnpm typecheck
pnpm dev                      # wrangler dev --env pl

# 5. Deploy
pnpm deploy:pl
```

## Cron (maintenance window, §10.3)

Configured in `wrangler.jsonc` under each `env.<league>.triggers.crons`. One
nightly maintenance trigger per league (`runMaintenance`: teams → fixtures →
standings → score cache warm, in order):

| Cron        | League    | Job                              |
|-------------|-----------|----------------------------------|
| `0 4 * * *` | PL, ELC   | nightly maintenance (UTC window) |
| `0 3 * * *` | PD        | nightly maintenance (CET window) |

One cron per league keeps us under the Workers **free-plan cap of 5 cron
triggers per account**. Times are UTC, winter offset (safe — worst case runs 1h
early in summer, still the dead zone); CET leagues shift to `0 3 * * *`.

## Layout

```
worker/
  src/
    index.ts        HTTP app + scheduled() cron handler
    types.ts        domain types + league config accessor
    football.ts     Provider interface + football-data.org impl
    scores.ts       KV counter-pair score cache
    db.ts           D1 reads + sync upserts
    sync.ts         cron jobs (fixtures/standings/teams/warm)
    routes/         fixtures, scores, standings, teams
  configs/pl/       Premier League config (source of truth, mirrors env vars)
  schema.sql        D1 schema (teams, fixtures, standings)
  wrangler.jsonc    generic top level + per-league env
```
