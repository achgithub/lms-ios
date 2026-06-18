import Foundation

/// Local cache freshness windows, per resource. Inside a resource's TTL the app
/// answers from its own on-disk cache and never calls the Worker — so exploring
/// the app (relaunching, tab-switching, re-tapping refresh) can't generate
/// wasteful Worker traffic. Tuned here in one place; safe to tweak post-launch
/// from real usage without touching any logic.
///
/// These are *local* TTLs (Worker-call suppression). They are deliberately
/// separate from the revenue gate (AdGate) and from the Worker's own upstream
/// TTLs (a later pass).
enum CacheTTL {
    /// Live scores change minute-to-minute.
    static let scores: TimeInterval = 60
    /// The table only moves when matches finish.
    static let standings: TimeInterval = 30 * 60
    /// The schedule is near-static; only kickoff edits / postponements move it.
    static let fixtures: TimeInterval = 4 * 60 * 60
    /// Names / promotions change at most seasonally.
    static let teams: TimeInterval = 7 * 24 * 60 * 60

    /// App-side staleness threshold for auto-assign: if the held table is older
    /// than this, offer a (gated) refresh before assigning bottom-of-table. A
    /// different job from `standings` above, so a different number on purpose.
    static let autoAssignTableStale: TimeInterval = 60 * 60
}

/// On-disk cache for per-league sports data, so browsing the Scores / Standings
/// screens and running rounds shows the last fetched data without hitting the
/// network. The explicit, ad-gated refresh fetches fresh gated data (scores,
/// table) and overwrites the cache; functional data (fixtures, teams) refreshes
/// itself only once its local TTL (see `CacheTTL`) lapses. Either way a fresh
/// launch reads the cache rather than re-fetching — closing the "relaunch for a
/// free refresh" back door.
enum LeagueDataCache {
    /// One league's scores snapshot.
    struct Scores: Codable {
        let date: Date
        let items: [ScoreItem]
        let teams: [TeamDTO]
    }

    /// One league's standings snapshot.
    struct Standings: Codable {
        let date: Date
        let rows: [StandingDTO]
        let teams: [TeamDTO]
    }

    /// One league's fixtures (schedule) snapshot — functional/free data.
    struct Fixtures: Codable {
        let date: Date
        let items: [FixtureDTO]
    }

    /// One league's teams snapshot — functional/free, near-static data.
    struct Teams: Codable {
        let date: Date
        let items: [TeamDTO]
    }

    /// Marks when a league's *live* match data (scores or results) was last
    /// pulled from the Worker — shared by every screen that does that job
    /// (Scores tab, Results entry's "Pull results from server"), even though
    /// they hit different endpoints (/scores vs /fixtures). Without this each
    /// screen had its own independent 60s clock, so a manager could pull twice
    /// in quick succession by switching screens.
    struct LivePull: Codable {
        let date: Date
    }

    /// Outcome of a cache read. Distinguishes "nothing cached yet" (normal first
    /// run) from "a file was there but unreadable" (corrupt write, or written by
    /// an older app version whose schema no longer decodes). Lets callers recover
    /// from corruption with a free fetch instead of an ad — it's our bad data, not
    /// a user-requested refresh.
    enum Read<T> {
        case hit(T)
        case empty
        case corrupt
    }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LeagueData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    /// Health-checked read: if a file exists but won't decode (corrupt or an old
    /// schema), it's **deleted on the spot** — so it can't linger, be half-read,
    /// or trip us again — and `.corrupt` is returned so the caller can recover
    /// with a free fetch rather than gating it behind an ad.
    static func read<T: Decodable>(_ type: T.Type, key: String) -> Read<T> {
        let fileURL = url(key)
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return .corrupt
        }
        return .hit(value)
    }

    /// Convenience that collapses `read` to an optional (corrupt → nil, and the
    /// bad file is still deleted by `read`). Use `read` directly where you need to
    /// tell corruption apart from a normal first-run miss.
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        if case .hit(let value) = read(type, key: key) { return value }
        return nil
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    /// True when a snapshot's timestamp is within the given local TTL — i.e. the
    /// app can serve it without calling the Worker (see `CacheTTL`).
    static func isFresh(_ date: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(date) < ttl
    }

    static func scoresKey(_ leagueId: String) -> String { "scores-\(leagueId)" }
    static func standingsKey(_ leagueId: String) -> String { "standings-\(leagueId)" }
    static func fixturesKey(_ leagueId: String) -> String { "fixtures-\(leagueId)" }
    static func teamsKey(_ leagueId: String) -> String { "teams-\(leagueId)" }
    static func livePullKey(_ leagueId: String) -> String { "live-pull-\(leagueId)" }

    /// The soonest moment a live-data pull (Scores tab or Results entry) could
    /// fetch something newer for this league. `nil` if no pull has happened yet
    /// or its 60s window has lapsed.
    static func livePullThrottleUntil(_ leagueId: String) -> Date? {
        guard case .hit(let pull) = read(LivePull.self, key: livePullKey(leagueId)),
              isFresh(pull.date, ttl: CacheTTL.scores) else { return nil }
        return pull.date.addingTimeInterval(CacheTTL.scores)
    }

    /// Record that a live-data pull just happened for this league (call after a
    /// successful fetch from either Scores or Results entry).
    static func recordLivePull(_ leagueId: String) {
        save(LivePull(date: Date()), key: livePullKey(leagueId))
    }

    /// Shared cooldown across every screen that pulls live match data (Scores
    /// tab, Results entry). `nil` (pull available now) if any league hasn't
    /// been pulled yet or its window has lapsed; otherwise the earliest expiry
    /// across the given leagues — matching how each screen previously computed
    /// its own (now-shared) throttle.
    static func sharedLiveThrottleUntil(for leagueIds: [String]) -> Date? {
        var earliest: Date?
        for id in leagueIds {
            guard let expiry = livePullThrottleUntil(id) else { return nil }
            earliest = earliest.map { min($0, expiry) } ?? expiry
        }
        return earliest
    }
}
