import Foundation

/// A snapshot of the provider data the round-flow screens need, fetched together.
/// Supports one or several leagues at once (a game can blend leagues): the
/// fixtures/teams/standings of every league are merged. football-data team and
/// fixture ids are globally unique, so merging by id is safe.
struct LeagueData {
    let fixtures: [FixtureDTO]
    let teamsById: [Int: TeamDTO]
    let standingsByTeam: [Int: StandingDTO]
    /// teamId → its league's team count (so weak-pick is correct across a blend).
    let teamsCountByTeam: [Int: Int]
    /// teamId → leagueId, to resolve which league a team/fixture belongs to.
    let leagueIdByTeam: [Int: String]

    /// Load and merge data for a set of leagues (a game's leagues).
    static func load(for leagues: [LeagueOption]) async throws -> LeagueData {
        let targets = leagues.isEmpty ? [Leagues.home] : leagues

        var fixtures: [FixtureDTO] = []
        var teamsById: [Int: TeamDTO] = [:]
        var standingsByTeam: [Int: StandingDTO] = [:]
        var teamsCountByTeam: [Int: Int] = [:]
        var leagueIdByTeam: [Int: String] = [:]

        // Per league the 3 calls run concurrently; leagues are merged in turn
        // (1–3 leagues typically, so sequential merge is fine).
        for league in targets {
            let client = league.client
            async let fixturesReq = client.fixtures()
            async let teamsReq = client.teams()
            async let standingsReq = client.standings()
            let (f, t, s) = try await (fixturesReq, teamsReq, standingsReq)

            fixtures.append(contentsOf: f)
            for team in t {
                teamsById[team.externalId] = team
                teamsCountByTeam[team.externalId] = league.teamsCount
                leagueIdByTeam[team.externalId] = league.id
            }
            for standing in s { standingsByTeam[standing.teamId] = standing }
        }

        return LeagueData(
            fixtures: fixtures,
            teamsById: teamsById,
            standingsByTeam: standingsByTeam,
            teamsCountByTeam: teamsCountByTeam,
            leagueIdByTeam: leagueIdByTeam
        )
    }

    /// Convenience for a single league.
    static func load(for league: LeagueOption) async throws -> LeagueData {
        try await load(for: [league])
    }
}
