import CryptoKit
import Foundation
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Apple App Attest client. Proves to each league Worker that requests come from
/// a genuine instance of this app, so the licensed football-data feed can't be
/// scraped through the open proxy (see worker/src/attest.ts + docs/app-attest-status.md).
///
/// Per-host keys: each league is a separate Worker with its own challenge secret
/// and device store, so we keep one attested Secure-Enclave key **per host**,
/// attested against that host's challenge and registered with that host. The same
/// app instance therefore holds a small set of keys (one per league Worker).
///
/// Best-effort by design: if attestation can't be produced (Simulator — App Attest
/// is unsupported there — or a transient error) we attach no headers and let the
/// Worker decide. This keeps the app working before the Worker starts enforcing,
/// and never hard-blocks the UI on an attestation hiccup. There is deliberately NO
/// `#if DEBUG` bypass: a real device (even a Debug build) performs real attestation,
/// so no free pass is ever compiled in.
actor AppAttestService {
    static let shared = AppAttestService()

    /// Header names — must match the Worker middleware (middleware/attest.ts).
    enum Header {
        static let keyId = "X-Attest-Key-Id"
        static let challenge = "X-Attest-Challenge"
        static let assertion = "X-Attest-Assertion"
    }

    private let defaults = UserDefaults.standard
    private let keyIdsDefaultsKey = "appattest.keyIdsByHost"
    private let challengeTTL: TimeInterval = 4 * 60

    /// host → cached challenge (challenges are valid ~5 min server-side; refresh early).
    private var challengeCache: [String: (value: String, fetched: Date)] = [:]
    /// host → in-flight key attestation, so concurrent requests share one enrolment.
    private var attestationTasks: [String: Task<String, Error>] = [:]

    /// Headers to attach to a request to `baseURL`, or `[:]` if attestation is
    /// unavailable. Never throws — failures degrade to an unattested request.
    func authorizationHeaders(for baseURL: URL) async -> [String: String] {
        #if canImport(DeviceCheck)
        guard DCAppAttestService.shared.isSupported, let host = baseURL.host else { return [:] }
        do {
            let keyId = try await attestedKeyId(host: host, baseURL: baseURL)
            let challenge = try await challenge(host: host, baseURL: baseURL)
            let assertion = try await assertion(keyId: keyId, challenge: challenge)
            return [
                Header.keyId: keyId,
                Header.challenge: challenge,
                Header.assertion: assertion,
            ]
        } catch {
            return [:]
        }
        #else
        return [:]
        #endif
    }

    #if canImport(DeviceCheck)
    private var service: DCAppAttestService { .shared }

    // MARK: - Key enrolment (attest + register), once per host

    private func attestedKeyId(host: String, baseURL: URL) async throws -> String {
        if let existing = storedKeyId(for: host) { return existing }
        if let inFlight = attestationTasks[host] { return try await inFlight.value }

        let task = Task<String, Error> {
            let keyId = try await service.generateKey()
            // Attest the new key against a fresh challenge from this host.
            let challengeValue = try await fetchChallenge(baseURL: baseURL)
            let attestation = try await service.attestKey(
                keyId, clientDataHash: clientDataHash(challengeValue)
            )
            try await register(
                baseURL: baseURL, keyId: keyId,
                attestation: attestation.base64EncodedString(), challenge: challengeValue
            )
            storeKeyId(keyId, for: host)
            return keyId
        }
        attestationTasks[host] = task
        defer { attestationTasks[host] = nil }
        return try await task.value
    }

    // MARK: - Assertion over a server challenge

    private func assertion(keyId: String, challenge: String) async throws -> String {
        let assertion = try await service.generateAssertion(
            keyId, clientDataHash: clientDataHash(challenge)
        )
        return assertion.base64EncodedString()
    }

    private func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }
    #endif

    // MARK: - Challenge cache

    private func challenge(host: String, baseURL: URL) async throws -> String {
        if let cached = challengeCache[host], Date().timeIntervalSince(cached.fetched) < challengeTTL {
            return cached.value
        }
        let value = try await fetchChallenge(baseURL: baseURL)
        challengeCache[host] = (value, Date())
        return value
    }

    // MARK: - Worker enrolment endpoints (unattested)

    private struct ChallengeResponse: Decodable { let challenge: String }

    private func fetchChallenge(baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("attest/challenge"))
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    private func register(baseURL: URL, keyId: String, attestation: String, challenge: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("attest/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "keyId": keyId, "attestation": attestation, "challenge": challenge,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - Per-host keyId persistence

    private func storedKeyId(for host: String) -> String? {
        (defaults.dictionary(forKey: keyIdsDefaultsKey) as? [String: String])?[host]
    }

    private func storeKeyId(_ keyId: String, for host: String) {
        var map = (defaults.dictionary(forKey: keyIdsDefaultsKey) as? [String: String]) ?? [:]
        map[host] = keyId
        defaults.set(map, forKey: keyIdsDefaultsKey)
    }
}
