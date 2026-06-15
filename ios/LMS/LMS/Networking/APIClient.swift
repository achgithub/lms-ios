import Foundation

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid request URL."
        case .badStatus(let code): return "Server returned status \(code)."
        }
    }
}

/// Client for a per-league Worker (read-only sports-data API). `shared` targets
/// the app's home league (LeagueConfig); browse screens that let the user switch
/// leagues (e.g. Scores) build a client per league via `init(baseURL:)`.
actor APIClient {
    static let shared = APIClient(baseURL: LeagueConfig.shared.workerURL)

    private let base: URL
    private let decoder = JSONDecoder()

    init(baseURL: URL) { self.base = baseURL }

    func teams() async throws -> [TeamDTO] { try await get("/teams") }
    func standings() async throws -> [StandingDTO] { try await get("/standings") }
    // One shared cache server-side — no freshness tier. Free vs subscriber is an
    // app-side rewarded-ad gate on the refresh action (see AdGate), not the data.
    func scores() async throws -> [ScoreDTO] { try await get("/scores") }

    func fixtures(dateFrom: String? = nil, dateTo: String? = nil, matchday: Int? = nil) async throws -> [FixtureDTO] {
        var query: [String] = []
        if let dateFrom { query.append("dateFrom=\(dateFrom)") }
        if let dateTo { query.append("dateTo=\(dateTo)") }
        if let matchday { query.append("matchday=\(matchday)") }
        let path = "/fixtures" + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
        return try await get(path)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base.absoluteString + path) else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return try decoder.decode(T.self, from: data)
    }
}
