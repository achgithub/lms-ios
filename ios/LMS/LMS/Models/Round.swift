import Foundation
import SwiftData

/// One round of a game, linked to real fixture matchdays by football-data ids.
@Model
final class Round {
    @Attribute(.unique) var id: UUID
    var roundNumber: Int
    var roundTypeRaw: String
    var fixtureIds: [Int]
    var deadline: Date
    var statusRaw: String
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Pick.round)
    var picks: [Pick] = []

    init(
        roundNumber: Int,
        deadline: Date,
        fixtureIds: [Int] = [],
        roundType: RoundType = .normal,
        game: Game? = nil
    ) {
        self.id = UUID()
        self.roundNumber = roundNumber
        self.deadline = deadline
        self.fixtureIds = fixtureIds
        self.roundTypeRaw = roundType.rawValue
        self.statusRaw = RoundStatus.open.rawValue
        self.game = game
    }

    /// The league(s) this round draws from = its game's leagues.
    var leagues: [LeagueOption] { game?.leagues ?? [Leagues.home] }

    var status: RoundStatus {
        get { RoundStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    var roundType: RoundType {
        get { RoundType(rawValue: roundTypeRaw) ?? .normal }
        set { roundTypeRaw = newValue.rawValue }
    }
}
