import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
/// Supports one or several leagues at once (a game can blend leagues): the
/// fixtures/teams/standings of every league are merged. football-data team and
/// fixture ids are globally unique, so merging by id is safe.
///
/// Every resource is served **cache-first** so that running rounds never spams
/// the Worker and never silently hands a free user fresh data:
/// - **Teams / fixtures** (functional, free) refresh from the Worker only once
///   their local TTL (`CacheTTL`) lapses; otherwise the on-disk snapshot is used.
/// - **Standings** (the table — gated) is *only ever read from cache* here, so
///   opening Picks/Results can't be a free table refresh. The sole exception is
///   an empty/corrupt cache, which gets one free fill (first-install rule). The
///   gated refresh lives elsewhere (Standings tab, or the auto-assign prompt via
///   `refreshStandings`).
struct LeagueData {
    let fixtures: [FixtureDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]
    /// teamId → its league's team count (so weak-pick is correct across a blend).
    let teamsCountByTeam: [Int: Int]
    /// Age marker for the table: the **oldest** standings snapshot across the
    /// game's leagues (nil only if a league had no table at all). Drives the
    /// auto-assign staleness prompt.
    let standingsDate: Date?

    /// Load and merge data for a set of leagues (a game's leagues).
    static func load(for leagues: [LeagueOption]) async throws -> LeagueData {
        let targets = leagues.isEmpty ? [Leagues.home] : leagues

        var fixtures: [FixtureDTO] = []
        var teamsById: [Int: TeamDTO] = [:]
        var standingsByTeam: [Int: StandingDTO] = [:]
        var teamsCountByTeam: [Int: Int] = [:]
        var oldestStandings: Date?

        // 1–3 leagues typically, so a sequential merge is fine.
        for league in targets {
            let teams = try await cachedTeams(for: league)
            let f = try await cachedFixtures(for: league)
            let (rows, date) = try await cachedStandings(for: league, teams: teams)

            // Stamped here, not inferred later from team-roster membership — see
            // FixtureDTO.leagueId's doc comment for why that matters.
            fixtures.append(contentsOf: f.map { fixture in
                var tagged = fixture
                tagged.leagueId = league.id
                return tagged
            })
            for team in teams {
                teamsById[team.externalId] = team
                teamsCountByTeam[team.externalId] = league.teamsCount
            }
            for standing in rows { standingsByTeam[standing.teamId] = standing }
            if let date { oldestStandings = min(oldestStandings ?? date, date) }
        }

        return LeagueData(
            fixtures: fixtures,
            teamsById: teamsById,
            standingsByTeam: standingsByTeam,
            teamsCountByTeam: teamsCountByTeam,
            standingsDate: oldestStandings
        )
    }

    /// Convenience for a single league.
    static func load(for league: LeagueOption) async throws -> LeagueData {
        try await load(for: [league])
    }

    /// Canonical "pull live data" for one league — the single action every
    /// screen that refreshes live match info shares (Scores tab's refresh,
    /// Results entry's "Pull results from server"), so a manager is never
    /// asked to watch a rewarded ad twice for the same underlying fetch.
    /// Fetches /scores + /fixtures + /teams once, writes the Scores cache
    /// (the priority/canonical snapshot), and patches the Fixtures cache for
    /// any now-FINISHED match so Open Round / Picks / Results entry see it
    /// without a separate fetch. Pure cache refresh: callers decide what to
    /// do with the result (e.g. Results entry still requires the manager to
    /// review and confirm before Close Round applies anything).
    static func pullLiveScores(for league: LeagueOption) async throws -> (items: [ScoreItem], teams: [TeamDTO]) {
        let client = league.client
        async let scoresReq = client.scores()
        async let fixturesReq = client.fixtures()
        async let teamsReq = client.teams()
        let (scores, fixtures, teams) = try await (scoresReq, fixturesReq, teamsReq)

        let metaById = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = scores.map { ScoreItem(score: $0, fixture: metaById[$0.id], leagueId: league.id) }
        // Same empty-response guard as cachedTeams/cachedFixtures: a "blocked"
        // league or a transient upstream hiccup must never look like the
        // scores cache just emptied out. recordLivePull still happens either
        // way — the throttle clock reflects the pull attempt, not its outcome.
        let existing = LeagueDataCache.load(LeagueDataCache.Scores.self, key: LeagueDataCache.scoresKey(league.id))
        if items.isEmpty, let existing, !existing.items.isEmpty {
            LeagueDataCache.recordLivePull(league.id)
            return (existing.items, existing.teams)
        }
        LeagueDataCache.save(
            LeagueDataCache.Scores(date: Date(), items: items, teams: teams),
            key: LeagueDataCache.scoresKey(league.id)
        )
        LeagueDataCache.recordLivePull(league.id)

        let finished = fixtures.filter { $0.status == "FINISHED" }
        patchFixturesCache(for: league, finished: finished)

        return (items, teams)
    }

    /// Merges freshly-pulled FINISHED fixtures into the existing Fixtures
    /// cache by id, leaving everything else untouched. No-op if there's
    /// nothing cached yet (the next normal fixtures load will fill it).
    private static func patchFixturesCache(for league: LeagueOption, finished: [FixtureDTO]) {
        guard !finished.isEmpty else { return }
        let key = LeagueDataCache.fixturesKey(league.id)
        guard let cached = LeagueDataCache.load(LeagueDataCache.Fixtures.self, key: key) else { return }
        let finishedById = Dictionary(uniqueKeysWithValues: finished.map { ($0.id, $0) })
        let merged = cached.items.map { finishedById[$0.id] ?? $0 }
        LeagueDataCache.save(LeagueDataCache.Fixtures(date: Date(), items: merged), key: key)
    }

    /// Gated, forced refresh of the league table(s) — fetches fresh standings from
    /// the Worker and overwrites the per-league cache that `cachedStandings` (and
    /// the Standings tab) read. Call from behind `AdGate`. Best-effort per league:
    /// a league that fails to refresh keeps its previous cached table.
    static func refreshStandings(for leagues: [LeagueOption]) async {
        for league in (leagues.isEmpty ? [Leagues.home] : leagues) {
            let client = league.client
            guard let rows = try? await client.standings(),
                  let teams = try? await client.teams() else { continue }
            // Same empty-response guard as cachedTeams/cachedFixtures — a
            // "blocked" league must keep its last real table, not show blank.
            if rows.isEmpty {
                let key = LeagueDataCache.standingsKey(league.id)
                if let existing = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key), !existing.rows.isEmpty {
                    continue
                }
            }
            LeagueDataCache.save(
                LeagueDataCache.Standings(date: Date(), rows: rows, teams: teams),
                key: LeagueDataCache.standingsKey(league.id)
            )
        }
    }

    // MARK: - Per-resource cache-first loaders

    /// Teams: functional/free. Served from cache within its TTL; otherwise fetched
    /// and re-cached. On a fetch failure with any cached copy, the stale copy is
    /// used rather than failing the whole load.
    private static func cachedTeams(for league: LeagueOption) async throws -> [TeamDTO] {
        let key = LeagueDataCache.teamsKey(league.id)
        switch LeagueDataCache.read(LeagueDataCache.Teams.self, key: key) {
        case .hit(let cached) where LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.teams):
            return cached.items
        case .hit(let cached):
            return (try? await fetchTeams(league, key: key, fallback: cached.items)) ?? cached.items
        case .empty, .corrupt:
            return try await fetchTeams(league, key: key, fallback: [])
        }
    }

    // `fallback` covers a *successful but empty* response (e.g. the league is in
    // its close-season "blocked" window — see seasonPhase.ts — and the Worker is
    // correctly serving its current store as-is). That must never overwrite a
    // cache that already has real data; only a genuinely fresh/non-empty result
    // gets written. A network failure is handled separately, by the caller's `try?`.
    private static func fetchTeams(_ league: LeagueOption, key: String, fallback: [TeamDTO]) async throws -> [TeamDTO] {
        let teams = try await league.client.teams()
        if teams.isEmpty, !fallback.isEmpty { return fallback }
        LeagueDataCache.save(LeagueDataCache.Teams(date: Date(), items: teams), key: key)
        return teams
    }

    /// Fixtures: functional/free. Cache-first within TTL. Falls back to a stale
    /// copy on a fetch failure, or on a successful-but-empty response, when one
    /// exists — see the `fallback` note on `fetchTeams` above; same reasoning.
    private static func cachedFixtures(for league: LeagueOption) async throws -> [FixtureDTO] {
        let key = LeagueDataCache.fixturesKey(league.id)
        let cached = LeagueDataCache.load(LeagueDataCache.Fixtures.self, key: key)
        if let cached, LeagueDataCache.isFresh(cached.date, ttl: CacheTTL.fixtures) {
            return cached.items
        }
        do {
            let fixtures = try await league.client.fixtures()
            if fixtures.isEmpty, let cached { return cached.items }
            LeagueDataCache.save(LeagueDataCache.Fixtures(date: Date(), items: fixtures), key: key)
            return fixtures
        } catch {
            if let cached { return cached.items }
            throw error
        }
    }

    /// Standings (the table — gated): read from cache **only**, regardless of age,
    /// so a round-flow open is never a free table refresh. The staleness prompt /
    /// gated refresh handles freshness. An empty or corrupt cache gets one free
    /// fill (first-install rule), writing the same cache the Standings tab uses.
    private static func cachedStandings(
        for league: LeagueOption,
        teams: [TeamDTO]
    ) async throws -> ([StandingDTO], Date?) {
        let key = LeagueDataCache.standingsKey(league.id)
        if case .hit(let cached) = LeagueDataCache.read(LeagueDataCache.Standings.self, key: key) {
            return (cached.rows, cached.date)
        }
        // Empty or corrupt → free first fill (reusing the teams we already loaded).
        let rows = try await league.client.standings()
        let now = Date()
        LeagueDataCache.save(LeagueDataCache.Standings(date: now, rows: rows, teams: teams), key: key)
        return (rows, now)
    }
}
