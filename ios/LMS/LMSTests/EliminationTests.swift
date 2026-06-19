import Testing
import Foundation
@testable import LMS

struct EliminationTests {

    @Test func lossEliminatesOthersSurvive() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        let picks = [
            PickOutcome(playerId: a, result: .loss),
            PickOutcome(playerId: b, result: .win),
            PickOutcome(playerId: c, result: .draw),
            PickOutcome(playerId: d, result: .postponed),
            PickOutcome(playerId: e, result: nil),
        ]
        // Default rules: draw eliminates, postponed survives (§6.5a).
        let result = GameEngine.computeEliminations(picks: picks, drawEliminates: true, postponedEliminates: false)
        #expect(Set(result.eliminatedPlayerIds) == Set([a, c]))
        #expect(Set(result.survivingPlayerIds) == Set([b, d, e]))
    }

    @Test func resultRulesAreConfigurable() {
        let a = UUID(), b = UUID()
        let picks = [
            PickOutcome(playerId: a, result: .draw),
            PickOutcome(playerId: b, result: .postponed),
        ]
        let lenient = GameEngine.computeEliminations(picks: picks, drawEliminates: false, postponedEliminates: false)
        #expect(lenient.eliminatedPlayerIds.isEmpty)
        #expect(Set(lenient.survivingPlayerIds) == Set([a, b]))

        let strict = GameEngine.computeEliminations(picks: picks, drawEliminates: true, postponedEliminates: true)
        #expect(Set(strict.eliminatedPlayerIds) == Set([a, b]))
        #expect(strict.survivingPlayerIds.isEmpty)
    }

    @Test func detectsAllEliminated() {
        #expect(GameEngine.isAllEliminated(activeBefore: 3, eliminatedThisRound: 3))
        #expect(!GameEngine.isAllEliminated(activeBefore: 3, eliminatedThisRound: 2))
        #expect(!GameEngine.isAllEliminated(activeBefore: 0, eliminatedThisRound: 0))
    }
}
