# Pricing model

Status: **decided (2026-06-18)**. Supersedes any earlier £2.99/£4.49/£5.99
"Manager/Club/Pro" ladder mentioned in older notes — this is current.

## The ladder

| Tier | Leagues | UK (£) | Eurozone (€) |
|---|---|---|---|
| Free | 1 (home league, PL by default) | £0 (ads) | €0 |
| No Ads | 1 league | £2.49/mo | €2.99/mo |
| 3 Leagues | 3 leagues | £3.49/mo | €3.99/mo |
| Unlimited | all leagues (= 3 today, grows with the catalogue) | £5.99/mo or £42.00/yr | €6.49/mo or €42.50/yr |

- Eurozone is GBP face-value **+€0.50**, not an FX conversion — set per-region in
  App Store Connect, not computed.
- USD pricing not yet decided — separate task before US launch.
- **No mid-season price hikes on existing subscribers.** Apple grandfathers
  existing subscribers when you raise a price anyway — a hike only ever
  affects *new* subscribers — so this is the real launch price, not a
  low-ball promo to raise later. Treat each season as the actual pricing
  experiment; revisit the ladder between seasons using real RevenueCat
  conversion data, not more modelling.

## Known temporary gap

"3 Leagues" and "Unlimited" are functionally identical right now — only 3
leagues exist (PL/ELC/PD). Unlimited is priced on *future* value (the
catalogue is built to grow past 3 — see the generic league architecture),
not on current cost-to-serve, since extra leagues barely move infra cost
(see below). Expect close to zero real differentiation or uptake for
Unlimited until a 4th+ league ships — that's expected, not a bug.

## Implementation status (app side done, 2026-06-18)

`Entitlements.Tier` is `free` / `no_ads` / `three_league` / `unlimited`,
matching this ladder. `PurchaseOption` (tier + `BillingPeriod`) represents
one purchasable RevenueCat package — needed because Unlimited offers two
billing lengths sharing one entitlement.

**RevenueCat/App Store Connect package identifiers to create** (4 products,
not the 6 first floated — No Ads and 3 Leagues don't get an annual option
at launch):

| Package id | Tier (entitlement) | Billing |
|---|---|---|
| `no_ads` | `no_ads` | monthly (no suffix — will never have an annual option) |
| `three_league_monthly` | `three_league` | monthly (suffixed now so adding annual later needs no app change) |
| `unlimited_monthly` | `unlimited` | monthly |
| `unlimited_annual` | `unlimited` | annual, £42.00/yr |

Still open: confirm these exact identifiers in the RevenueCat dashboard
match `PurchaseOption.packageId`; set the real API key
(`PurchaseService.apiKey`); add the SPM packages in Xcode (RevenueCat +
Google Mobile Ads) — see [[lms-monetization]] for that activation checklist.

## The cost/revenue model behind the decision

### Per-request infra load (measured from the actual worker code)

One "pull live data" tap (`LeagueData.pullLiveScores`, hits `/scores`
`/fixtures` `/teams`) = **per league, per tap**:
- 3 Workers requests
- 7 KV reads (`/scores`: 3 gate + 1 blob; `/fixtures`: 3 gate; `/teams`: 0)
- ~420 D1 rows read (`/fixtures` full season ~400 rows + `/teams` ~20 rows)

Client-side cooldown is 120s, shared across the Scores tab and Results
entry's "Pull results from server" (bumped from 60s earlier in the same
session that produced this doc — see the worker's `SCORE_TTL_SECONDS`).

### Cost stack modelled

- Cloudflare Workers Paid: $5/mo base, 10M requests included, $0.30/M beyond
- Cloudflare KV: 10M reads/month included, $0.50/M beyond
- Cloudflare D1: 25 billion rows read/month included, $0.001/M beyond
  (never matters in practice at any scale modelled)
- football-data.org subscription: $30/mo flat (given, not derived)
- Apple Developer Program: £75/yr ≈ $7.94/mo amortised
- A dev-tooling subscription (Claude Max 5x, $100/mo) — **deliberately
  deferred**, see phasing below

### Key finding: Cloudflare variable cost is never the real risk

Workers + KV + D1 combined stay under $625/month even at 500,000 users on
the heaviest engagement assumption tested. The actual *outage* risk was the
free-tier Workers 100k-requests/day cap (shared across all three league
workers) — solved by moving to Workers Paid, not by any usage-throttling
feature. Per-subscriber marginal infra cost is ~$0.0004–0.012/month —
trivial against any plausible subscription price (1,000x+ margin). Pricing
a tier higher for more leagues is **not** justified by infra cost — extra
leagues cost pennies more; the justification is value/willingness-to-pay,
not cost recovery.

### Fixed-cost phasing decision

Don't add the Claude Max subscription as a modelled cost until the app is
past roughly:
- **~250–500 total users** (conservative uptake), or
- **~100 users** (optimistic uptake)

Adding it too early can flip an otherwise-profitable early scenario into a
loss: the fixed-cost floor is ~$38/mo "early phase" (football-data $30 +
Apple Dev ~$8) vs ~$138/mo "growth phase" once Claude Max is added.

### Breakeven user counts (this ladder, this cost stack)

| Scenario | Conservative uptake | Optimistic uptake |
|---|---|---|
| With subscriptions, early phase (no Claude) | ~126 users | ~31 users |
| With subscriptions, growth phase (+ Claude Max) | ~418 users | ~100 users |

**Ads-only, zero subscribers ever** (the absolute floor) swings hugely on
the free-user engagement assumption:

| Engagement assumption | Early phase | Growth phase |
|---|---|---|
| Light (30% engaged, 8 taps/day, 8 active days/mo) | ~689 users | ~2,291 users |
| **Moderate (50% engaged, 15 taps/day, 12 active days/mo) — settled-on assumption** | **~147 users** | **~489 users** |
| Heavy/hammering (80% engaged, 30 taps/day, 20 active days/mo) | ~28 users | ~92 users |

Moderate was chosen as realistic: "the average manager will trigger a few
extra refreshes during matches" — not a light, occasional checker, and not
someone hammering the refresh button nonstop.

### Uptake profiles used (speculative — no real data yet)

- **Conservative:** Free 90%, No Ads 7%, 3-League 2.5%, Unlimited 0.5%.
- **Optimistic:** Free 55%, No Ads 25%, 3-League 15%, Unlimited 5%.

### Ad revenue's share of total revenue

~16.4% under conservative uptake vs ~2.4% under optimistic uptake. Ads are
a floor / cost-offset, not the engine — subscriptions dominate once any
meaningful conversion happens. (Assumptions: $5 eCPM cautious estimate,
65% ad fill+completion rate.)

### Price elasticity — tried, inconclusive by design

A constant-elasticity demand curve was tried first and discarded: that
curve shape mathematically always pushes the "optimal" price to one edge
of whatever range you test, which isn't a real insight. Switched to an
exponential-decay demand curve, which does produce a genuine interior
revenue-maximising price — but that "optimal" price swings from roughly $1
to $6 depending on an unknowable sensitivity assumption. No robust
conclusion beyond: **this needs real RevenueCat A/B price-testing data
post-launch, not more spreadsheet modelling.**

### Portfolio context

Multiple apps are planned on shared Cloudflare/Apple/RevenueCat
infrastructure. Other planned apps are lighter (static page-publishing, no
API backend), so this particular cost stack doesn't repeat per-app — the
football-data subscription and API-related Cloudflare costs are specific
to apps with a live sports-data backend like this one.
