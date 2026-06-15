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
        let result = GameEngine.computeEliminations(picks: picks)
        #expect(result.eliminatedPlayerIds == [a])
        #expect(Set(result.survivingPlayerIds) == Set([b, c, d, e]))
    }

    @Test func detectsAllEliminated() {
        #expect(GameEngine.isAllEliminated(activeBefore: 3, eliminatedThisRound: 3))
        #expect(!GameEngine.isAllEliminated(activeBefore: 3, eliminatedThisRound: 2))
        #expect(!GameEngine.isAllEliminated(activeBefore: 0, eliminatedThisRound: 0))
    }
}
