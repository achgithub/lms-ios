# App Attest — status & plan

Status: **UNBLOCKED — build starting** (2026-06-17). Individual Apple Developer
Program membership approved 2026-06-17.

- **Team ID: `UD928WR9RR`** (team name "Andrew Harris", individual). Active
  2026-06-17 → expires 2027-06-17.
- **Bundle: `com.sportsmanager.LMS`.**
- A Team ID is **not secret** (it ships in every app), so in the Worker it is a
  plain config var, not a rotated secret. Only `ATTEST_CHALLENGE_KEY` is secret.

This is Phase 2 of the release security work. Phase 1 (custom domains +
workers.dev lockdown + zone rate-limiting) is done and shipped. See also
`docs/data-refresh-and-caching.md`.

## Progress

**Worker side — BUILT (2026-06-17), NOT deployed.** Code complete, typechecks,
unit-tested (challenge HMAC), and bundles for workerd (581 KiB / 104 KiB gzip).
- `worker/src/attest.ts` — stateless HMAC challenge issue/verify; attestation
  verify (CBOR decode, Apple cert-chain, nonce, keyId, rpId, AAGUID); assertion
  verify (ECDSA-P256 sig + monotonic counter). Apple root CA pinned.
- `worker/src/attest-store.ts` — D1 device store (public key + sign_count).
- `worker/src/attest-config.ts` — config + the `ATTEST_DEV_BYPASS` dev escape.
- `worker/src/routes/attest.ts` — `POST /attest/challenge`, `POST /attest/register`.
- `worker/src/middleware/attest.ts` — guard mounted on `/fixtures /scores
  /standings /teams` only (`index.ts`); `/health` + `/admin` left open.
- `schema.sql` — `attest_devices` table. Libs: `@levischuck/tiny-cbor` (pure JS),
  `@peculiar/x509@^1.x` (v2 needs a reflect-metadata polyfill — avoided).

> ⚠️ **DO NOT `wrangler deploy` the Worker yet.** Deploying now would (a) reject
> the current live app, which sends no attestation headers, and (b) 500 on data
> routes because `ATTEST_CHALLENGE_KEY` is unset. Deploy only once the app side
> ships and is verified, in the coordinated go-live step below.

**App side — BUILT (2026-06-17), compiles; on-device test pending.**
- `ios/LMS/LMS/Networking/AppAttest.swift` — `AppAttestService` actor. Per-host
  Secure-Enclave keys (each league Worker has its own challenge secret + device
  store): generate key → attest against the host's challenge → `POST /attest/register`
  → persist keyId per host; per request fetch/cache a challenge + generate an
  assertion. Attaches `X-Attest-Key-Id/Challenge/Assertion`.
- `APIClient.get()` switched to `URLRequest` and attaches those headers.
- `LMS.entitlements` — `com.apple.developer.devicecheck.appattest-environment` =
  `$(APP_ATTEST_ENVIRONMENT)`; pbxproj sets it `development` (Debug) / `production`
  (Release), matching the Worker's `APP_ATTEST_ENV`. `CODE_SIGN_ENTITLEMENTS` wired
  on both app configs.
- **Bypass = `DCAppAttestService.isSupported`** (false on Simulator), NOT `#if DEBUG`
  — a real device (incl. Debug builds) performs real attestation, so no free pass is
  compiled in. Best-effort: any failure → no headers → the Worker decides (keeps the
  app working pre-enforcement, never hard-blocks the UI).
- ✅ Compiles (`xcodebuild` Simulator, signing off). **Still needs:** App Attest
  capability enabled on the `com.sportsmanager.LMS` App ID in the Developer portal,
  then a real-device run to verify enrolment + assertion end-to-end.

### Go-live sequence (when app side is ready)
1. `wrangler secret put ATTEST_CHALLENGE_KEY --env pl` (and elc/pd) — random 32+ byte value.
2. Apply schema to add `attest_devices`: `pnpm db:apply:pl` (+ elc/pd).
3. Ship the app build that performs attestation (still `APP_ATTEST_ENV=development`
   for devicectl test builds).
4. `wrangler deploy --env pl` (+ elc/pd). Verify the app works end-to-end and that
   an unattested `curl` to `/scores` now gets 401.
5. At App Store release: flip `APP_ATTEST_ENV` → `production` and redeploy.

---

## Why

The three Workers (`pl|elc|pd.sportsmanager.site`) are currently an **open proxy**:
`/scores`, `/teams`, `/fixtures`, `/standings` return data to anyone — no auth, only
the zone rate-limit caps volume.

The goal is **not confidentiality** (the data is public). It is to protect the
**licensed football-data.org feed** from being scraped for free through our open
proxy, which risks breaching the provider's terms. App Attest is the good-faith
measure: only the genuine iOS app can reach the feed. The `FOOTBALL_DATA_TOKEN`
stays server-side as today — attestation guards the proxy, not the token.

football-data.org licence obligation = **attribution only**, already shipped
(commit `c19fd59`, Settings → About credit).

---

## Decisions locked

### Challenge model = HMAC stateless

The Worker issues a one-time-ish challenge = `random nonce + timestamp`,
**HMAC-signed** with a new secret `ATTEST_CHALLENGE_KEY`, with a short validity
window (~60s). The app embeds it in the assertion; the Worker re-derives and
verifies the HMAC + freshness.

- **Not** KV-stored nonces: KV writes hit the free-plan **1,000/day** cap and add
  hot-path latency. HMAC is pure CPU and scales on free **and** paid plans (moving
  to paid Cloudflare does *not* make KV the better choice — verified).
- **Replay protection** = per-device public key + **monotonic counter persisted in
  D1**; reject if the counter doesn't advance. This is the real anti-replay and
  works regardless of how challenges are issued.
- **Net new secret added by Phase 2: exactly one — `ATTEST_CHALLENGE_KEY`.**

### App Attest requires a paid Apple Developer Program account

It cannot run on a free personal Apple ID team — the "App Attest" App ID
capability and the `com.apple.developer.devicecheck.appattest-environment` entitlement
are not available to personal teams (same restriction class as Push/iCloud). Verified
against live Apple docs/forums 2026-06-17.

### Team ID + bundle are configurable, not hardcoded

App Attest bakes `appID = TeamID.bundleID` into every attestation. The Worker pins
**Team ID + bundle `com.sportsmanager.LMS`**, stored as **config (env var / secret),
not hardcoded** — the pinned Team ID must match the account that signs the
**release** build. Keeping it configurable means go-live (and any future Team ID
change) is a one-value update, not a rebuild.

### Account route = individual now → in-place convert to organization later

- Enrol **individual** ($99/yr, **no DUNS**, ~24–48h) to get a real Team ID fast.
  **(Order placed 2026-06-17.)**
- Later do the **in-place "Convert to Organization"** (Account Holder → Membership
  Details → *Submit a request* → *Convert to Organization*). Needs the
  limited-company DUNS + Tax ID, but **preserves the same Team ID** and carries over
  apps / bundle IDs / IAPs (re-invite collaborators).
- **Do NOT** create a separate org account and use "Transfer App" — that **changes
  the Team ID** and would break App Attest (the Worker pin + every attested device
  key).
- Confirm with Apple Developer Support at enrolment that the Team ID survives the
  conversion (well-established, but no primary-source quote found; our configurable
  pin de-risks it either way).
- Andrew runs everything through his limited company → consider doing the conversion
  **before meaningful revenue** for clean company accounts.

---

## What unblocks the build (Andrew's side)

1. ✅ Individual Apple Developer Program enrolment — **order placed 2026-06-17**,
   awaiting approval.
2. When approved: grab the **10-char Team ID** (Developer portal → Membership
   details).
3. Enable **App Attest** on the `com.sportsmanager.LMS` App ID (portal →
   Certificates, IDs & Profiles → App ID → tick **App Attest**). Assistant will walk
   through the Xcode/profile side.
4. (Optional) Ask Apple Developer Support to confirm Team ID is preserved through a
   future Convert-to-Organization.

Then hand the Team ID to the assistant and the build proceeds in one pass.

---

## Build plan (when unblocked)

### App side (iOS 17, real device only — `DCAppAttestService` does not run in sim/debug)

1. Generate a hardware key, attest it once, persist the `keyId`.
2. Per session/request, send an **assertion** signed over the server-issued
   challenge/nonce (stops replay).
3. Attach attestation headers in `ios/LMS/LMS/Networking/APIClient.swift` — currently
   a bare `URLSession.shared.data(from:)`, so switch to `URLRequest`. Per-league base
   URL comes from `Leagues.swift` / `leagues.json`.
4. Any dev bypass **must** be `#if DEBUG`-gated and must never ship (cf. the
   `c022f3b` free-Pro bypass that had to be fixed — do not repeat).

### Worker side (Hono, `worker/src/`)

5. Attestation **middleware on data routes only** — `index.ts` mounts `/fixtures`
   `/scores` `/standings` `/teams` (lines 29–32). Leave `/health` and `/admin`
   (own token in `auth.ts`) alone.
6. **Challenge endpoint**: issue the HMAC-signed nonce (see decision above).
7. **Verify attestation**: CBOR-decode, validate the cert chain to Apple's App
   Attest root CA, pin Team ID + bundle `com.sportsmanager.LMS`, store device public
   key + counter in D1. Verify each assertion (signature over nonce, counter
   monotonic). Reject unattested → 401/403.
8. `nodejs_compat` is on — check whether CBOR / X.509 chain validation needs a lib
   or WebCrypto is enough (verify against live Cloudflare docs).
9. The Worker dev bypass must also be gated behind a dev-only condition that is
   impossible in the deployed build; verify it's absent from prod.

### Secrets (rotate as one batch at the very end of the build, per Andrew's plan)

`FOOTBALL_DATA_TOKEN`, freshly-rotated `ADMIN_TOKEN`, and the new
`ATTEST_CHALLENGE_KEY`. Canonical copies stored in Andrew's password manager. Do not
rotate mid-build.

---

## Android — Play Integrity, future work (discussed 2026-06-19, not built)

App Attest is **Apple-only** — there is no Android equivalent to *this specific*
API. Android's analogous mechanism is Google's **Play Integrity API**, a
different protocol with its own verification flow. Once App Attest enforcement
is switched on for `pl`/`elc`/`pd`, an Android app would always get
`401 attestation required` with no possible fix, because it cannot produce an
Apple App Attest assertion.

**This is fine and doesn't block iOS shipping with App Attest now.** The two
platforms need separate, additive verification paths, added when Android
actually exists:

- **No iOS recoding required, ever.** The iOS app only ever sends
  `X-Attest-Key-Id`/`X-Attest-Challenge`/`X-Attest-Assertion` and has no
  awareness of Android. Adding Android support never touches this.
- **The Worker DOES need new code, but additive, not a rewrite:** a second
  verification branch in `middleware/attest.ts` (route by which headers a
  request carries — iOS headers vs a future `X-Play-Integrity-Token`), a new
  `verifyPlayIntegrity()` function calling Google's API, and a parallel device
  table alongside `attest_devices` (the verdict shape differs). New config
  needed then: Android package name + Google Cloud project number (mirrors
  `APP_ATTEST_TEAM_ID`/`APP_ATTEST_BUNDLE_ID`).
- **Considered and rejected for now:** pre-building a stub `play-integrity.ts`
  file + dead branch ahead of any Android client existing. Decided against —
  speculative scaffolding for an undecided integration shape, with no actual
  protective value (the "no iOS recoding" guarantee holds regardless of
  whether a stub exists).

**The actual risk worth managing is deploying to a Worker already serving live
iOS customers, not Android's code shape.** Concrete safeguards for when that
work starts:
1. Confirm `attest.test.ts` actually exercises `requireAttestation` (the
   middleware), not just the lower-level crypto helpers — add coverage first if
   not, so a future edit to add the Android branch can't silently regress the
   iOS path without a test catching it.
2. Hard rule: Android verification work must be additive-only — new
   file(s), new branch gated on a header iOS never sends, **zero edits** to
   the existing iOS functions (`verifyAssertion`, `verifyChallenge`,
   `getDevice`, etc.). If a diff for "add Android" touches anything inside the
   current iOS code paths, that's the review red flag.
3. Deploy discipline: `pnpm typecheck && pnpm test` first, then redeploy
   `pl`/`elc`/`pd`, then immediately smoke-test the live iOS flow (a real
   attested request) before walking away — same as any change to a shared
   backend.

## Maintenance mode — planned, deferred to Beta/TestFlight (decided 2026-06-19)

Also discussed: during a live worker deploy, a temporary failure on a data
route currently looks like a generic error to the app — risks a support call.
A deliberate "we're doing maintenance" response, recognized by the app, turns
that into an expected, reassuring state instead. **Not built — revisit at the
Beta/TestFlight phase** (see the route-to-live Phase 4 notes elsewhere).

**Decided scope:**
- **Routes:** only the app-relevant data APIs (`/fixtures /scores /standings
  /teams`) — NOT `/health` or `/admin`, which must keep working so the flag
  itself stays controllable.
- **Granularity: GLOBAL across pl/elc/pd, not per-league.** Reasoning: a
  manager often has several leagues active in one session — 1-of-3 leagues
  failing while 2 succeed is *more* confusing than all three being down
  together with one clear message. This is a deliberate deviation from the
  rest of the codebase's per-league KV pattern (demo clock, gates, etc. are
  all per-league) — worth remembering when designing the actual toggle
  mechanism, since it needs shared state across three separate Worker
  deployments, not three independent KV flags.

**Sketched design (not built):** a KV-stored `maintenance:on` flag, toggled via
an admin-token-gated `/admin/maintenance/on|off` endpoint (no redeploy needed
to flip it — flip on → deploy the risky change → verify → flip off).
Middleware returns a distinct, structured response (e.g.
`503 {"error":"maintenance","message":"..."}`) that the app recognizes and
shows a friendly state for, separate from its generic error handling.

## References

- football-data.org licence: attribution only (shipped, `c19fd59`).
- Apple — Preparing to use the App Attest service:
  https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service
- Convert Individual → Organization (DUNS required):
  https://help.uscreen.tv/en/articles/8284333-convert-apple-developer-account-from-individual-to-business
