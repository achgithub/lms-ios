import Foundation

/// Game lifecycle. Stored as raw strings on the SwiftData models (robust against
/// schema/predicate quirks); the models expose typed computed wrappers.
enum GameStatus: String, Codable, CaseIterable { case setup, active, complete }

enum PlayerStatus: String, Codable, CaseIterable { case active, eliminated, winner }

enum RoundStatus: String, Codable, CaseIterable { case open, picks, results, closed }

enum RoundType: String, Codable, CaseIterable, Identifiable {
    case normal, playoff, rollover
    var id: String { rawValue }
    /// Label for the open-round screen when this round is a tie follow-up.
    var openTitle: String {
        switch self {
        case .normal: return "Round"
        case .playoff: return "Playoff Round"
        case .rollover: return "Rollover Round"
        }
    }
}

enum PickResult: String, Codable, CaseIterable { case win, draw, loss, postponed }

/// Summary-card anonymity, set once at game creation (spec §13b.2).
enum AnonymityMode: String, Codable, CaseIterable, Identifiable {
    case anonymous, named
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anonymous: return "Anonymous"
        case .named: return "Named"
        }
    }
}
