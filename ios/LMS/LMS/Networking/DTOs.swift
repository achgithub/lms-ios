import Foundation

/// Wire types returned by the Worker (already camelCase JSON). Read-only — the
/// cloud serves only provider-sourced sports data.

struct TeamDTO: Decodable, Identifiable {
    let id: String
    let externalId: Int
    let name: String
    let shortName: String?
    let tla: String?
    let leagueId: String
}

struct FixtureDTO: Decodable, Identifiable {
    let id: Int
    let matchday: Int?
    let kickoff: String
    let status: String
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?
    let winner: String?
    let updatedAt: String
}

struct StandingDTO: Decodable, Identifiable {
    let teamId: Int
    let position: Int
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDifference: Int
    let points: Int
    let updatedAt: String

    var id: Int { teamId }
}

struct ScoreDTO: Decodable, Identifiable {
    let id: Int
    let status: String
    let minute: Int?
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?
    let winner: String?
}
