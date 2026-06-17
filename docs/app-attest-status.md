# App Attest — status & plan

Status: **design agreed, build deferred** (2026-06-17). Blocked only on the Apple
Developer Program account being approved and the Team ID being known. **Individual
enrolment order placed 2026-06-17** — resume when the Team ID lands.

This is Phase 2 of the release security work. Phase 1 (custom domains +
workers.dev lockdown + zone rate-limiting) is done and shipped. See also
`docs/data-refresh-and-caching.md`.

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
capability and the `com.apple.developer.app-attest.environment` entitlement are not
available to personal teams (same restriction class as Push/iCloud). Verified
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

## References

- football-data.org licence: attribution only (shipped, `c19fd59`).
- Apple — Preparing to use the App Attest service:
  https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service
- Convert Individual → Organization (DUNS required):
  https://help.uscreen.tv/en/articles/8284333-convert-apple-developer-account-from-individual-to-business
