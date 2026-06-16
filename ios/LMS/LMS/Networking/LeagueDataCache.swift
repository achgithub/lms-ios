import Foundation

/// On-disk cache for per-league sports data, so browsing the Scores / Standings
/// screens shows the last fetched data without hitting the network. Only the
/// explicit, ad-gated refresh fetches fresh data and overwrites the cache — which
/// closes the "relaunch for a free refresh" back door (a fresh launch reads the
/// cache, it doesn't re-fetch).
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

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LeagueData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    static func scoresKey(_ leagueId: String) -> String { "scores-\(leagueId)" }
    static func standingsKey(_ leagueId: String) -> String { "standings-\(leagueId)" }
}
