import Foundation

/// How a tie / all-eliminated round was resolved, for the outcome card.
enum OutcomeEnding: String, Codable, CaseIterable {
    case winner          // a clean last-one-standing finish
    case split           // multi-way tie split into joint winners
    case rollWeek        // the tied survivors roll the week and replay
    case everyoneBackIn  // everyone reinstated, picks reset

    var sectionLabel: String {
        switch self {
        case .winner, .split: return AppString("RESULT")
        case .rollWeek, .everyoneBackIn: return AppString("NO CLEAR WINNER")
        }
    }

    var headline: String {
        switch self {
        case .winner: return AppString("🏆 WINNER")
        case .split: return AppString("🏆 JOINT WINNERS")
        case .rollWeek: return AppString("⏭️ ROLL THE WEEK")
        case .everyoneBackIn: return AppString("🔄 EVERYONE BACK IN")
        }
    }

    /// Heading above the player list on the card.
    var listHeading: String {
        switch self {
        case .winner: return AppString("Takes it all")
        case .split: return AppString("Pot is split")
        case .rollWeek: return AppString("Still in — pick again")
        case .everyoneBackIn: return AppString("Back in, picks reset")
        }
    }
}

/// Which summary card to render (spec §13b.1).
enum SummaryType: Equatable {
    case fixtures // the round's matches — shared so players know what to pick from
    case picks    // who picked what — after the deadline / picks finalised
    case results  // who survived / went out — after the round closed
    case outcome(OutcomeEnding)  // how a tie / all-eliminated round resolved

    var sectionLabel: String {
        switch self {
        case .fixtures: return AppString("FIXTURES")
        case .picks: return AppString("PICKS")
        case .results: return AppString("RESULTS")
        case .outcome(let ending): return ending.sectionLabel
        }
    }
}

/// One match on the fixtures card.
struct SummaryFixture: Identifiable {
    let id: Int
    let homeTla: String?
    let awayTla: String?
    let homeName: String
    let awayName: String
    let kickoff: Date?
}

/// One team's pick group for the Picks summary (spec §13b.3).
struct SummaryTeamGroup: Identifiable {
    let teamId: Int
    let tla: String?
    let teamName: String
    let playerNames: [String]   // alphabetical; manager (if known) carries a flag
    let includesManager: Bool

    var count: Int { playerNames.count }
    var id: Int { teamId }
}

/// Flattened, render-ready snapshot for `SummaryCardView`. Built on the main
/// actor from the SwiftData models + provider team data so the card view itself
/// stays a pure function of plain values (renders cleanly under `ImageRenderer`).
struct SummaryData {
    let type: SummaryType
    let mode: AnonymityMode
    let leagueName: String
    let appName: String
    let gameName: String
    let roundNumber: Int
    let timestampLabel: String

    // Picks summary
    let pickGroups: [SummaryTeamGroup]

    // Results summary (this round)
    let survivors: [String]
    let eliminated: [String]
    let managerSurvived: Bool
    let managerEliminated: Bool

    // Outcome summary (tie / all-eliminated resolution)
    let outcome: OutcomeEnding?
    let outcomePlayers: [String]   // winners, carried-forward, or everyone

    // Fixtures summary (the round's matches)
    let fixtures: [SummaryFixture]

    // Footer (game-level standing)
    let activeCount: Int
    let eliminatedCount: Int

    /// Watermark domain — TBC in the spec (§13b.6); placeholder until confirmed.
    static let watermarkDomain = "lms-pl.app"

    var nextRoundNumber: Int { roundNumber + 1 }

    static func make(
        type: SummaryType,
        game: Game,
        round: Round,
        teamsById: [Int: TeamDTO],
        roundFixtures: [FixtureDTO] = [],
        managerPlayerId: UUID? = nil
    ) -> SummaryData {
        func name(_ team: Int) -> String {
            teamsById[team]?.shortName ?? teamsById[team]?.name ?? "Team \(team)"
        }
        func displayName(_ player: Player) -> String { player.name }

        // Fixtures: the round's matches, sorted by kick-off.
        let summaryFixtures: [SummaryFixture] = roundFixtures
            .map { f in
                SummaryFixture(
                    id: f.id,
                    homeTla: teamsById[f.homeTeamId]?.tla,
                    awayTla: teamsById[f.awayTeamId]?.tla,
                    homeName: name(f.homeTeamId),
                    awayName: name(f.awayTeamId),
                    kickoff: FixtureFormat.kickoffDate(f.kickoff)
                )
            }
            .sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }

        // Picks: group this round's picks by team, count descending.
        var byTeam: [Int: [Player]] = [:]
        for pick in round.picks {
            guard let player = pick.player else { continue }
            byTeam[pick.teamId, default: []].append(player)
        }
        let pickGroups: [SummaryTeamGroup] = byTeam.map { teamId, players in
            let sorted = players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return SummaryTeamGroup(
                teamId: teamId,
                tla: teamsById[teamId]?.tla,
                teamName: name(teamId),
                playerNames: sorted.map(displayName),
                includesManager: managerPlayerId.map { id in sorted.contains { $0.id == id } } ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
        }

        // Results: derive this round's outcome from the picks (loss = out).
        var survived: [Player] = []
        var eliminated: [Player] = []
        for pick in round.picks {
            guard let player = pick.player else { continue }
            switch pick.result {
            case .loss: eliminated.append(player)
            case .win, .draw, .postponed: survived.append(player)
            case .none: break
            }
        }
        let survivorsSorted = survived.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let eliminatedSorted = eliminated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let activeNow = game.players.filter { $0.status == .active || $0.status == .winner }.count
        let eliminatedNow = game.players.filter { $0.status == .eliminated }.count

        // Outcome: which players to name depends on the ending. Names respect the
        // game's anonymity setting ("Player 3" when anonymous).
        let anonymous = game.anonymityMode == .anonymous
        var outcome: OutcomeEnding?
        var outcomePlayers: [String] = []
        if case .outcome(let ending) = type {
            outcome = ending
            let relevant: [Player]
            switch ending {
            case .winner, .split:    relevant = game.players.filter { $0.status == .winner }
            case .rollWeek:          relevant = game.players.filter { $0.status == .active }
            case .everyoneBackIn:    relevant = game.players
            }
            outcomePlayers = relevant
                .sorted { $0.entryNumber < $1.entryNumber }
                .map { $0.displayName(anonymous: anonymous) }
        }

        return SummaryData(
            type: type,
            mode: game.anonymityMode,
            leagueName: game.leagueLabel,
            appName: LeagueConfig.shared.appName,
            gameName: game.name,
            roundNumber: round.roundNumber,
            timestampLabel: timestampLabel(for: type, round: round),
            pickGroups: pickGroups,
            survivors: survivorsSorted.map(displayName),
            eliminated: eliminatedSorted.map(displayName),
            managerSurvived: managerPlayerId.map { id in survived.contains { $0.id == id } } ?? false,
            managerEliminated: managerPlayerId.map { id in eliminated.contains { $0.id == id } } ?? false,
            outcome: outcome,
            outcomePlayers: outcomePlayers,
            fixtures: summaryFixtures,
            activeCount: activeNow,
            eliminatedCount: eliminatedNow
        )
    }

    private static func timestampLabel(for type: SummaryType, round: Round) -> String {
        let formatter = DateFormatter()
        // Locale-aware so the weekday/month read in the selected in-app language.
        formatter.locale = Bundle.appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        switch type {
        case .fixtures: return AppString("Picks due · \(formatter.string(from: round.deadline))")
        case .picks:    return AppString("Picks locked · \(formatter.string(from: round.deadline))")
        case .results, .outcome: return AppString("Full time · \(formatter.string(from: Date()))")
        }
    }
}
