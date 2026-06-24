import Foundation

/// CSV export for a game's full history — a manual backup, not a restore format.
/// Two files: game-level settings, and one row per round × player × pick. Pure
/// and testable; `GameExportView` handles writing to disk and presenting the
/// share sheet.
enum GameExportCSV {
    /// Game-level settings as key/value rows — the rules a manual scorer would
    /// need to keep running the game by hand (league, repeats, draw handling).
    static func metadataCSV(for game: Game) -> String {
        var lines: [String] = []
        func row(_ key: String, _ value: String) { lines.append([key, value].map(escape).joined(separator: ",")) }

        row("Game Name", game.name)
        row("Season", game.season)
        row("Leagues", game.leagues.map(\.name).joined(separator: "; "))
        row("Allow Repeats", game.allowRepeats ? "true" : "false")
        row("Draw Eliminates", game.drawEliminates ? "true" : "false")
        row("Postponed Eliminates", game.postponedEliminates ? "true" : "false")
        row("Status", game.status.label)
        let winners = game.players.filter { $0.status == .winner }
        if !winners.isEmpty {
            row("Winner", winners.map(\.name).joined(separator: ", "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per round × player: their pick that round (if any), the team's
    /// match time, and the result. Player status is the current/final status,
    /// repeated across every row — this is a snapshot, not a status history.
    static func picksCSV(for game: Game, data: LeagueData) -> String {
        let header = ["Round Number", "Player", "Player Status", "Team Picked", "Match Time", "Pick Result"]
        var lines = [header.map(escape).joined(separator: ",")]

        let rounds = game.rounds.sorted { $0.roundNumber < $1.roundNumber }
        let players = game.players.sorted { $0.entryNumber < $1.entryNumber }

        for round in rounds {
            let fixtureIds = Set(round.fixtureIds)
            let roundFixtures = data.matches.filter { fixtureIds.contains($0.id) }

            for player in players {
                let pick = round.picks.first { $0.player?.id == player.id }
                let pickedTeamName = pick.flatMap { teamName(for: $0.teamId, data: data) }
                let matchTime = pick
                    .flatMap { p in roundFixtures.first { $0.homeTeamId == p.teamId || $0.awayTeamId == p.teamId } }
                    .flatMap { FixtureFormat.kickoffDate($0.kickoff) }
                    .map(Self.timeFormatter.string(from:))

                let fields = [
                    String(round.roundNumber),
                    player.name,
                    player.status.label,
                    pickedTeamName ?? "",
                    matchTime ?? "",
                    pick?.result.map(resultLabel) ?? "",
                ]
                lines.append(fields.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func teamName(for teamId: Int, data: LeagueData) -> String? {
        guard let team = data.teamsById[teamId] else { return nil }
        return team.shortName ?? team.name
    }

    nonisolated private static func resultLabel(_ result: PickResult) -> String {
        switch result {
        case .win: return "Win"
        case .draw: return "Draw"
        case .loss: return "Loss"
        case .postponed: return "Postponed"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    /// Wraps a field in quotes only if it needs it (contains a comma, quote, or newline).
    /// `nonisolated` so it can be called from the plain (non-`@MainActor`) closures
    /// above — it touches no actor-isolated state.
    nonisolated private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
