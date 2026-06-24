# LSM v2 architecture sketch

Status: **design sketch, not yet implemented** (2026-06-24). v1 (Last Man
Standing, single mode, SwiftData-local) keeps shipping/supported throughout —
see [Repo strategy](#5-repo-strategy-and-v1-support) below. As of 2026-06-24,
priority has shifted to v2 — estimated at roughly a week's build given how
much groundwork (cloud data model, submission flow, league scale decision)
is already settled here. The only v1 work still planned is the CSV export
(§6) before attention moves fully to the v2 fork.

LSM = "Last Stand Manager," the app-level brand. v2 adds a second game mode
("Predictor") alongside the existing one (now named "LMS" at the mode level).
Both modes live in one app, one subscription, one cloud backend.

---

## 1. The two modes

### LMS (Last Man Standing)
Existing elimination game, ported to be cloud-backed instead of
SwiftData-local. One pick per round per player; wrong (or non-)pick
eliminates; last player standing wins. Round/Pick/Player shape carries over
largely as-is from v1 — see `ios/LMS/LMS/Models/{Game,Round,Pick,Player}.swift`
— just re-homed so the source of truth is D1, not on-device.

### Predictor
New season-long game. Each week, players predict the score of each fixture
in scope. Points awarded per fixture (exact split TBD, working example:
1 pt correct outcome + 1 pt correct home score + 1 pt correct away score).
Points accumulate across the season into a standings table, published the
same way league tables are today. Unlike LMS, players are never eliminated —
they can join/leave mid-season, and the "game" is really a running league
table rather than a knockout.

Because Predictor only makes sense with season-long durable state survivable
across a phone change, it's cloud-backed from day one — which is what removes
the reason LMS needs to stay local-only too.

---

## 2. LSM Cloud (backend)

A Cloudflare Worker + D1, evolved from the existing read-only sports-data
Worker (`worker/` — currently `teams`, `fixtures`, `standings`,
`attest_devices`, `sync_meta`, all per-league config, no per-user state).

**Leagues + fixtures consolidation (v2-fork only):** v1 runs one D1 database
*per league* (`lms-pl-db`, `lms-bl1-db`, ...), each with its own
`teams`/`fixtures`/`standings` and a static `league.config.json` baked into
the worker bundle — there's no `leagues` table and no `league_id` column on
`fixtures` today, because the database itself is scoped to one league. v2
replaces the per-league-config-file model with a `leagues` table (name,
footballDataCode, TTLs, roundsPerSeason, region, etc. as rows instead of
files) and `league_id` columns on `teams`/`fixtures`/`standings`.
`teams.external_id` and `fixtures.id` are football-data.org's own ids and
are already globally unique across leagues, so no id-renumbering is needed.

**v1 is explicitly left as-is** — its per-league D1s are not migrated, not
touched, and keep running independently. This consolidation only happens in
the v2 fork's own (separate) infrastructure, avoiding any live-migration risk
to v1's production data.

**D1 topology (decided 2026-06-24, evaluated independently of v1's
precedent): regional sharding, not one global D1 and not one D1 per
league.** With ~2000 leagues worldwide a realistic ceiling, all three
options were weighed on their own merits:

- *One D1 per league* (v1's model) doesn't scale to thousands — Workers' D1
  bindings are static, configured at deploy time, so thousands of databases
  means either thousands of hardcoded bindings (unworkable) or falling back
  to D1's HTTP API for any cross-database access (slower, no binding-level
  performance, and a meta-system just to provision/manage that many
  databases).
- *One global D1* loses the maintenance-window benefit entirely — at 2000
  leagues spanning every timezone, it's always live hours *somewhere*, so
  there's no quiet period for migrations, and every write (sync crons,
  submissions, predictions) serializes through one writer queue with global
  blast radius on a bad lock/migration.
- *Regional shards* (UK standalone given Premier League's outsized query
  volume; separate shards for the rest of Europe, North America, South
  America, with more added as needed) hit the sweet spot: bounded blast
  radius per shard, real timezone-aligned maintenance windows (leagues
  within a region cluster around similar match-time hours), a small fixed
  number of static D1 bindings (4-6 to start, trivially expressible in
  wrangler config), and cross-league queries stay single-query for the
  realistic case (a player following leagues within their own region) —
  true cross-region queries are rare enough to eat the fan-out cost.

This adds one piece of real complexity neither extreme needs: something has
to know which shard a given `league_id` lives in before querying it — a
small static manifest (region per league, rarely changes) read once to pick
the right D1 binding. Per-league data is small enough (~20-30 teams, ~380
fixtures/season, ~20-30 standings rows) that this is purely an
isolation/maintenance-window decision, not a row-count one — even a single
global D1 would hold the data fine at 2000 leagues; regional sharding wins
on blast radius and ops, not raw capacity.

v2 adds tables that didn't exist before, because v1 deliberately kept all
game state on-device:

- `games` — id, mode (`lms` | `predictor`), league config, settings (allowRepeats,
  drawEliminates, scoring rules for Predictor, etc.), status.
- `players` — id, game_id, display name, status (active/eliminated for LMS;
  just "active" for Predictor since there's no elimination), join/leave dates.
- `picks` (LMS) — player_id, round_id, team_id, result.
- `predictions` (Predictor) — player_id, fixture_id, predicted_home_score,
  predicted_away_score, points_awarded.
- `submission_tokens` — player_id, uuid token (the player's unique link),
  created_at, revoked_at.
- `submissions` (the approval queue) — token_id, fixture/round context,
  payload (pick or prediction), status (pending/approved/rejected),
  submitted_at, decided_at.

Fixture/team/standings data stays shared and unchanged — both modes consume
the same upstream-sourced sports data the v1 Worker already maintains; the
new tables are purely the per-game/per-player layer v1 never needed.

**Open question:** whether v2's Worker is a new deployment (own D1, own
routes) that *also* pulls fixture data, or whether it reads fixture data
from the existing v1 D1/Worker via a service binding to avoid duplicating
the football-data.org sync logic. Leaning toward the latter (don't fetch the
same upstream data twice), but worth deciding once the v2 repo exists.

---

## 3. Player app (the PWA)

A lightweight shared web app, not tied to either mode specifically:

- Manager generates a unique link per player from inside LSM (mints a
  `submission_tokens` row). No email, no account — just an unguessable UUID,
  chosen specifically to avoid GDPR personal-data handling.
- Opening the link shows the player only what's actionable right now: for
  LMS, the current round's available teams; for Predictor, this week's
  fixtures awaiting a score guess.
- Submitting writes a row into `submissions` with status `pending` — it does
  **not** write directly into `picks`/`predictions`.
- The manager opens LSM, sees the queue, approves or rejects each entry.
  Approval is what actually creates the `pick`/`prediction` row; rejection
  discards it. This is the misuse gate — anyone with the link can submit, but
  nothing is live until the manager confirms it.
- Manager-typed entries (the manager entering a pick/prediction directly,
  on behalf of a player who isn't online) skip the queue entirely and write
  straight through — this is the permanent fallback for players who never
  self-submit, not a stopgap.

---

## 4. Cross-app subscriptions (v1 → v2)

**Decided 2026-06-24, chosen approach: Sign in with Apple as the identity
bridge.** A v1 subscriber shouldn't have to re-pay in v2. Apple doesn't share
subscriptions across different bundle IDs automatically, and RevenueCat's
multi-app entitlement sharing (multiple App Store apps under one RevenueCat
Project, entitlements visible across them) only works if both apps agree the
purchaser is the *same customer* — which requires a stable shared App User
ID. v1 is anonymous today (install-scoped ids), so there's nothing to bridge
on without adding *something*.

Sign in with Apple supplies that bridge without reopening the GDPR-light
design used elsewhere: it returns a stable, opaque per-developer-account
identifier (no real email required, even if the user picks "Hide My Email").
v1 and v2 both authenticate with it, RevenueCat recognizes the same customer
across both apps' entitlements, and the underlying subscription keeps
billing/renewing through whichever app's App Store record it was originally
purchased on — v2 just checks entitlement against the same RevenueCat
customer rather than requiring its own purchase.

Caveats accepted: (1) this is low-priority unless v1 actually gets enough
subscribers for it to matter — explicitly *not* blocking v2's build; (2) the
Apple-id-to-customer link can break if the user revokes app access from
their Apple ID settings or the developer Team ID changes — rare, not
bulletproof, acceptable given the low stakes today. Rejected alternative:
manual support-driven entitlement grants in the RevenueCat dashboard — works
at near-zero subscriber counts but doesn't scale, kept as a fallback for
edge cases rather than the primary mechanism.

---

## 5. Repo strategy and v1 support

v2 starts as a **separate git project (or fork of this repo)**, not built
in-place on `main`. v1 keeps shipping and being supported on its own
timeline — current TestFlight users aren't forced onto v2, and v1's
SwiftData-local, single-mode app keeps working exactly as it does today.
The fork point is where v1's iOS/Worker code gets carried over as the
starting skeleton for v2's cloud-backed rewrite; v1's repo continues to
receive its own fixes independently after that point (they diverge).

**Open question:** how long v1 keeps receiving fixes/features once v2 ships,
and whether v1 users get migrated into v2 or simply sunset over time. Not
needed to answer before starting v2, but worth deciding before App Store
submission of v2 (affects whether the v1 listing stays up alongside it).

---

## 6. Closing out v1

Before v2 work displaces attention: finish **game export for v1**
(`docs/lsm-v2-architecture.md` task tracker #1 — CSV export via ShareLink,
two files: game metadata + per-round pick history, designed to also support
a future "import/restore" path). This is the last planned v1 feature; v2
work starts after it lands.
