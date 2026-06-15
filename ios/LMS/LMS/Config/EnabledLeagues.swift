import Observation
import Foundation

/// The leagues the user has enabled (ticked in Settings). A game can use any of
/// these; Scores/Standings browse among them. How many can be enabled at once is
/// capped by the subscription (`Entitlements.leagueAllowance`): free = 1, paid =
/// the whole catalogue. Persisted in UserDefaults; never empty (falls back to the
/// home league). Observe via `@Environment(EnabledLeagues.self)`.
@Observable @MainActor
final class EnabledLeagues {
    static let shared = EnabledLeagues()

    private static let key = "enabledLeagueIds"

    private(set) var ids: [String]

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        let valid = saved.filter { Leagues.byId($0) != nil }
        ids = valid.isEmpty ? [Leagues.home.id] : valid
    }

    /// Enabled leagues, in registry order.
    var leagues: [LeagueOption] { Leagues.all.filter { ids.contains($0.id) } }

    func isEnabled(_ league: LeagueOption) -> Bool { ids.contains(league.id) }

    func enable(_ league: LeagueOption) {
        guard !ids.contains(league.id) else { return }
        ids.append(league.id)
        persist()
    }

    /// Replace the whole enabled set with a single league (used to SWAP the one
    /// league on a single-league plan). Callers handle any game-deletion confirm.
    func setOnly(_ league: LeagueOption) {
        ids = [league.id]
        persist()
    }

    /// Disable a league. Callers handle any destructive confirmation (deleting
    /// games that reference it) before calling. Never leaves the set empty.
    func disable(_ league: LeagueOption) {
        ids.removeAll { $0 == league.id }
        if ids.isEmpty { ids = [Leagues.home.id] }
        persist()
    }

    /// Drop leagues that no longer exist (never empty). Does NOT trim for the
    /// subscription allowance — going over allowance (e.g. a cancelled sub) is
    /// surfaced to the user so THEY choose which to keep (LeagueDowngradeView).
    func pruneInvalid() {
        ids = ids.filter { Leagues.byId($0) != nil }
        if ids.isEmpty { ids = [Leagues.home.id] }
        persist()
    }

    /// Whether the enabled count fits the subscription. When false the app must
    /// force the user to reduce their leagues before continuing.
    func isWithinAllowance(_ entitlements: Entitlements) -> Bool {
        ids.count <= entitlements.leagueAllowance
    }

    private func persist() { UserDefaults.standard.set(ids, forKey: Self.key) }
}
