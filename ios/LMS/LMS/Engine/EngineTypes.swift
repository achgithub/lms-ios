import Foundation

/// Pure value types for the game-logic engine. The engine has no SwiftData or
/// SwiftUI dependency — it operates on these plain inputs so it is fast and
/// deterministic to unit-test. A thin adapter maps the @Model objects to these.

/// A team in a round's fixtures, with its league position if standings are known.
nonisolated struct TeamRef: Equatable, Sendable {
    let id: Int
    let name: String
    let position: Int?   // nil when standings are unavailable
}

/// An active player's state needed for auto-assign: which team ids they've used
/// in previous closed rounds.
nonisolated struct PlayerAssignmentState: Equatable, Sendable {
    let id: UUID
    let usedTeamIds: Set<Int>
}

nonisolated struct AutoAssignInput: Sendable {
    let fixtureTeams: [TeamRef]
    let players: [PlayerAssignmentState]
    let allowRepeats: Bool
}

/// One player's pick result for elimination computation.
nonisolated struct PickOutcome: Equatable, Sendable {
    let playerId: UUID
    let result: PickResult?   // nil = unresolved (round shouldn't close yet)
}

nonisolated struct EliminationResult: Equatable, Sendable {
    let eliminatedPlayerIds: [UUID]
    let survivingPlayerIds: [UUID]
}

/// How a tie / all-eliminated round resolves. Chosen in the moment by the manager
/// (spec §13c). The adapter applies the outcome to the game.
nonisolated enum TieOutcome: Equatable, Sendable {
    /// Declare winner(s) and complete the game — a clean last-one-standing finish,
    /// a split of a multi-way tie, or a manager manual declaration.
    case winners([UUID])
    /// Roll the week: only the tied final survivors carry forward and replay.
    /// `resetPool` reopens their used-team history when they've exhausted it.
    case rollWeek(tiedIds: [UUID], resetPool: Bool)
    /// Everyone back in: reinstate every player and reset all used-team history.
    case everyoneBackIn(allIds: [UUID])
}
