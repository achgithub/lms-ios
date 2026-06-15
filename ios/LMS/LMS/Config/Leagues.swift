import Foundation

/// A league the user can browse live data for. The app's *game* is bound to one
/// home league (`LeagueConfig.shared`); these are the leagues whose Worker the
/// browse screens (Scores) can also query. Each is a separate Worker deployment
/// backed by a free-tier football-data feed.
struct LeagueOption: Identifiable, Hashable, Sendable {
    let id: String          // leagueId, e.g. "PL"
    let name: String        // display name, e.g. "Premier League"
    let shortName: String   // chip label, e.g. "PL"
    let workerBaseURL: URL

    var client: APIClient { APIClient(baseURL: workerBaseURL) }
}

enum Leagues {
    /// Every league with a live Worker. Keep in sync with the deployed envs in
    /// `worker/wrangler.jsonc` (one Worker per league).
    static let all: [LeagueOption] = [
        LeagueOption(id: "PL", name: "Premier League", shortName: "PL",
                     workerBaseURL: URL(string: "https://lms-pl-worker.sportsmanager.workers.dev")!),
        LeagueOption(id: "ELC", name: "Championship", shortName: "ELC",
                     workerBaseURL: URL(string: "https://lms-elc-worker.sportsmanager.workers.dev")!),
        LeagueOption(id: "PD", name: "La Liga", shortName: "PD",
                     workerBaseURL: URL(string: "https://lms-pd-worker.sportsmanager.workers.dev")!),
    ]

    /// The user's configured home league (the one the game uses); falls back to
    /// the first registered league if the config id isn't in the list.
    static var home: LeagueOption {
        all.first { $0.id == LeagueConfig.shared.leagueId } ?? all[0]
    }
}
