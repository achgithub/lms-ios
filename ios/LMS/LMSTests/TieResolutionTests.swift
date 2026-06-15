import Testing
import Foundation
import SwiftData
@testable import LMS

struct TieResolutionTests {

    // MARK: - Pure engine: pool exhaustion

    @Test func poolExhaustedWhenEveryTiedPlayerHasUsedEveryTeam() {
        #expect(GameEngine.poolExhausted(usedTeamCounts: [20, 20], totalTeams: 20))
        #expect(GameEngine.poolExhausted(usedTeamCounts: [21, 20], totalTeams: 20))
    }

    @Test func poolNotExhaustedWhenAnyPlayerHasTeamsLeft() {
        #expect(!GameEngine.poolExhausted(usedTeamCounts: [20, 19], totalTeams: 20))
        #expect(!GameEngine.poolExhausted(usedTeamCounts: [], totalTeams: 20))
        #expect(!GameEngine.poolExhausted(usedTeamCounts: [5], totalTeams: 0))
    }

    // MARK: - Apply outcomes (model-backed)

    private func makeGame() throws -> (ModelContext, Game) {
        let container = try ModelContainer(
            for: Game.self, Player.self, Round.self, Pick.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let game = Game(name: "T", season: "2025/26", allowRepeats: false)
        context.insert(game)
        // Round 4 is the tie round (the current round).
        let round = Round(roundNumber: 4, deadline: .now, game: game)
        context.insert(round)
        game.rounds.append(round)
        return (context, game)
    }

    private func addPlayer(_ name: String, to game: Game, context: ModelContext, status: PlayerStatus = .active) -> Player {
        let p = Player(name: name, game: game, entryNumber: game.nextEntryNumber)
        p.status = status
        context.insert(p)
        game.players.append(p)
        return p
    }

    @Test func splitMakesTiedPlayersJointWinnersAndCompletesGame() throws {
        let (context, game) = try makeGame()
        let a = addPlayer("A", to: game, context: context)
        let b = addPlayer("B", to: game, context: context)
        _ = addPlayer("C", to: game, context: context, status: .eliminated)

        let follow = GameLogicService.apply(.winners([a.id, b.id]), game: game)

        #expect(follow == nil)
        #expect(game.status == .complete)
        #expect(a.status == .winner && b.status == .winner)
        #expect(game.players.first { $0.name == "C" }?.status == .eliminated)
        #expect(game.lastOutcome == .split)
    }

    @Test func singleWinnerRecordsWinnerEnding() throws {
        let (context, game) = try makeGame()
        let a = addPlayer("A", to: game, context: context)
        GameLogicService.apply(.winners([a.id]), game: game)
        #expect(game.lastOutcome == .winner)
    }

    @Test func rollWeekReinstatesTiedAndResetsPoolWhenExhausted() throws {
        let (context, game) = try makeGame()
        let a = addPlayer("A", to: game, context: context, status: .eliminated)
        let b = addPlayer("B", to: game, context: context, status: .eliminated)

        let follow = GameLogicService.apply(.rollWeek(tiedIds: [a.id, b.id], resetPool: true), game: game)

        #expect(follow == .rollover)
        #expect(a.status == .active && b.status == .active)
        #expect(a.teamPoolResetAfterRound == 4 && b.teamPoolResetAfterRound == 4)
        #expect(game.lastOutcome == .rollWeek)
    }

    @Test func rollWeekDoesNotResetPoolWhenTeamsRemain() throws {
        let (context, game) = try makeGame()
        let a = addPlayer("A", to: game, context: context, status: .eliminated)

        GameLogicService.apply(.rollWeek(tiedIds: [a.id], resetPool: false), game: game)

        #expect(a.status == .active)
        #expect(a.teamPoolResetAfterRound == 0)
    }

    @Test func everyoneBackInReinstatesAllAndResetsEveryPool() throws {
        let (context, game) = try makeGame()
        let a = addPlayer("A", to: game, context: context, status: .eliminated)
        let b = addPlayer("B", to: game, context: context, status: .eliminated)
        let c = addPlayer("C", to: game, context: context, status: .eliminated)

        let follow = GameLogicService.apply(.everyoneBackIn(allIds: [a.id, b.id, c.id]), game: game)

        #expect(follow == .rollover)
        #expect(game.players.allSatisfy { $0.status == .active })
        #expect(game.players.allSatisfy { $0.teamPoolResetAfterRound == 4 })
        #expect(game.lastOutcome == .everyoneBackIn)
    }

    // MARK: - Used-team boundary

    @Test func usedTeamIdsExcludesPicksBeforeResetBoundary() throws {
        let (context, game) = try makeGame()
        let player = addPlayer("A", to: game, context: context)

        // A pick in round 2 (closed) and round 3 (closed).
        for (number, team) in [(2, 10), (3, 11)] {
            let round = Round(roundNumber: number, deadline: .now, game: game)
            round.status = .closed
            context.insert(round)
            game.rounds.append(round)
            let pick = Pick(teamId: team, player: player, round: round)
            context.insert(pick)
            player.picks.append(pick)
        }

        // No boundary → both teams counted.
        #expect(GameLogicService.usedTeamIds(for: player) == [10, 11])

        // Boundary after round 2 → only round 3's pick counts.
        player.teamPoolResetAfterRound = 2
        #expect(GameLogicService.usedTeamIds(for: player) == [11])
    }
}
