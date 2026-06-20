import Foundation

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid request URL."
        case .badStatus(let code, let body):
            guard let body, !body.isEmpty else { return "Server returned status \(code)." }
            return "Server returned status \(code): \(body)"
        }
    }
}

/// Client for a per-league Worker (read-only sports-data API). Each league
/// builds its own client via `LeagueOption.client` / `init(baseURL:)`.
actor APIClient {
    private let base: URL
    private let decoder = JSONDecoder()

    init(baseURL: URL) { self.base = baseURL }

    func teams() async throws -> [TeamDTO] { try await get("/teams") }
    func standings() async throws -> [StandingDTO] { try await get("/standings") }
    // One shared cache server-side — no freshness tier. Free vs subscriber is an
    // app-side rewarded-ad gate on the refresh action (see AdGate), not the data.
    func scores() async throws -> [ScoreDTO] { try await get("/scores") }

    func fixtures(dateFrom: String? = nil, dateTo: String? = nil, matchday: Int? = nil) async throws -> [FixtureDTO] {
        var query: [URLQueryItem] = []
        if let dateFrom { query.append(URLQueryItem(name: "dateFrom", value: dateFrom)) }
        if let dateTo { query.append(URLQueryItem(name: "dateTo", value: dateTo)) }
        if let matchday { query.append(URLQueryItem(name: "matchday", value: String(matchday))) }
        return try await get("/fixtures", query: query)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        // App Attest: prove this is the genuine app so the Worker serves the
        // licensed feed. Best-effort — no headers on Simulator / pre-enrolment,
        // and the Worker decides whether to accept (see AppAttestService).
        for (field, value) in await AppAttestService.shared.authorizationHeaders(for: base) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatus(-1, body: String(data: data, encoding: .utf8))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try decoder.decode(T.self, from: data)
    }
}
