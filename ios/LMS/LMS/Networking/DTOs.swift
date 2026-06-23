import Foundation

// Wire types returned by the Worker (already camelCase JSON). Read-only — the
// cloud serves only provider-sourced sports data.

// TeamDTO and StandingDTO are Codable so the league-data cache can persist them
// to disk (see DiskCache) — that's what makes browsing serve cached data and
// only the ad-gated refresh hit the network.
struct TeamDTO: Codable, Identifiable {
    let id: String
    let externalId: Int
    let name: String
    let shortName: String?
    let tla: String?
    let leagueId: String
}

// Codable (not just Decodable) so the league-data cache can persist fixtures to
// disk, the same way teams/standings are cached — see LeagueDataCache.
struct FixtureDTO: Codable, Identifiable {
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
    /// Which league this fixture was fetched from — absent on the wire (each
    /// Worker serves one league per request), so `LeagueData.load` stamps it
    /// right after fetching, before anything else sees it. Deliberately NOT
    /// inferred from team-roster membership: a promoted/relegated club can
    /// briefly appear in two leagues' team lists at once, which would
    /// mislabel a fixture based on roster-sync timing rather than which
    /// league it actually belongs to.
    var leagueId: String?
}

struct StandingDTO: Codable, Identifiable {
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
