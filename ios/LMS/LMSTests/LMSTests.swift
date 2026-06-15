//
//  LMSTests.swift
//  LMSTests
//

import Testing
import Foundation
@testable import LMS

/// Foundation tests for the models/enums. The deterministic rules engine
/// (auto-assign, eliminations, the five tie rules) gets its own dedicated tests
/// when it's ported in Phase 3 — these just lock in the building blocks.
struct ModelTests {

    @Test func newGameStartsInSetupWithNoPlayers() {
        let game = Game(name: "Office LMS", season: "2025/26", allowRepeats: false)
        #expect(game.status == .setup)
        #expect(game.players.isEmpty)
        #expect(game.currentRound == nil)
        #expect(game.lastOutcome == nil)
    }

    @Test func gameStatusWrapperRoundTrips() {
        let game = Game(name: "G", season: "2025/26", allowRepeats: true)
        game.status = .active
        #expect(game.statusRaw == "active")
        #expect(game.status == .active)
    }

    @Test func lastOutcomeWrapperRoundTrips() {
        let game = Game(name: "G", season: "2025/26", allowRepeats: true)
        game.lastOutcome = .rollWeek
        #expect(game.lastOutcomeRaw == "rollWeek")
        #expect(game.lastOutcome == .rollWeek)
    }

    @Test func newPlayerIsActiveWithCleanPool() {
        let player = Player(name: "Dave")
        #expect(player.status == .active)
        #expect(player.teamPoolResetAfterRound == 0)
    }

    @Test func anonymousDisplayNameUsesEntryNumber() {
        let player = Player(name: "Dave", entryNumber: 3)
        #expect(player.displayName(anonymous: false) == "Dave")
        #expect(player.displayName(anonymous: true) == "Player 3")
    }

    @Test func pickResultStartsNil() {
        let pick = Pick(teamId: 57)
        #expect(pick.result == nil)
        pick.result = .win
        #expect(pick.resultRaw == "win")
        #expect(pick.result == .win)
    }
}

struct LeagueConfigTests {

    @Test func bundledConfigLoadsForPremierLeague() {
        let config = LeagueConfig.shared
        #expect(config.leagueId == "PL")
        #expect(config.teamsCount == 20)
        #expect(config.workerURL.scheme == "https")
    }
}
