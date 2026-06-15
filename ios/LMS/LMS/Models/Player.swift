import Foundation
import SwiftData

/// A named player within a game. No app account — names only (spec §6.2).
/// Name uniqueness within a game is enforced in code at add time.
@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var name: String
    var statusRaw: String
    /// Stable per-game entry number, assigned at add time. Used to identify the
    /// player on anonymous summary cards ("Player 3") where names are withheld.
    var entryNumber: Int = 0
    /// Round number after which this player's used-team history counts. Bumped when
    /// a tie resolution reopens their team pool (roll-the-week exhaustion, or
    /// "everyone back in"), so they can re-pick teams they'd already used.
    var teamPoolResetAfterRound: Int = 0
    /// True for the app owner's own entry in a game (spec §13b.2 transparency ⚑).
    var isManager: Bool
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Pick.player)
    var picks: [Pick] = []

    init(name: String, game: Game? = nil, isManager: Bool = false, entryNumber: Int = 0) {
        self.id = UUID()
        self.name = name
        self.statusRaw = PlayerStatus.active.rawValue
        self.entryNumber = entryNumber
        self.teamPoolResetAfterRound = 0
        self.isManager = isManager
        self.game = game
    }

    var status: PlayerStatus {
        get { PlayerStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Name, or "Player N" when the card is anonymous (spec §13b.2).
    func displayName(anonymous: Bool) -> String {
        anonymous ? "Player \(entryNumber)" : name
    }
}
