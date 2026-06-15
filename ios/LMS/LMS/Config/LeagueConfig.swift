import Foundation

/// League configuration bundled with the app target. The app is generic; a
/// "league" is only this config (+ team-signatures.json). Premier League is the
/// first instance — see the project's app-driven architecture notes.
nonisolated struct LeagueConfig: Decodable, Sendable {
    let leagueId: String
    let leagueName: String
    let appName: String
    let workerBaseURL: String
    let teamsCount: Int
    let allowRepeatDefault: Bool
    let roundsPerSeason: Int
    let scoreTtlSubSeconds: Int
    let season: String

    /// Base URL of the per-league Worker (read-only sports-data API).
    var workerURL: URL {
        guard let url = URL(string: workerBaseURL) else {
            fatalError("Invalid workerBaseURL in league.config.json: \(workerBaseURL)")
        }
        return url
    }

    static let shared: LeagueConfig = load()

    private static func load() -> LeagueConfig {
        guard let url = Bundle.main.url(forResource: "league.config", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("league.config.json is missing from the app bundle")
        }
        do {
            return try JSONDecoder().decode(LeagueConfig.self, from: data)
        } catch {
            fatalError("Failed to decode league.config.json: \(error)")
        }
    }
}
