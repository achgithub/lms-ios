import Testing
import SwiftUI
import UIKit
@testable import LMS

/// Smoke test that the share cards render to a non-nil image via ImageRenderer
/// (the same path the app uses for export) — guards the marketing artifact
/// against a crash or empty render.
@MainActor
struct CardRenderTests {
    private func renders(_ data: SummaryData) -> Bool {
        let r = ImageRenderer(content: SummaryCardView(data: data))
        r.scale = 3
        return r.uiImage != nil
    }

    @Test func renderPicksCard() {
        let groups = [
            SummaryTeamGroup(teamId: 1, tla: "ARS", teamName: "Arsenal",
                             playerNames: ["Andy", "Dave", "Pete", "Sarah"], includesManager: true),
            SummaryTeamGroup(teamId: 2, tla: "MUN", teamName: "Man Utd",
                             playerNames: ["Chris", "Jake", "Lucy", "Mo", "Tom"], includesManager: false),
            SummaryTeamGroup(teamId: 3, tla: "CHE", teamName: "Chelsea",
                             playerNames: ["Nina"], includesManager: false),
        ]
        let data = SummaryData(
            type: .picks, mode: .named, leagueName: "England — Premier League",
            appName: "Last Man Standing", gameName: "The Office Pool", roundNumber: 3,
            timestampLabel: "Picks locked · Sat 16 Aug · 12:30", pickGroups: groups,
            survivors: [], eliminated: [], managerSurvived: false, managerEliminated: false,
            outcome: nil, outcomePlayers: [], fixtures: [], activeCount: 10, eliminatedCount: 2)
        #expect(renders(data))
    }

    @Test func renderFixturesCard() {
        let fx = [
            SummaryFixture(id: 1, homeTla: "ARS", awayTla: "CHE", homeName: "Arsenal",
                           awayName: "Chelsea", kickoff: .now),
            SummaryFixture(id: 2, homeTla: "MUN", awayTla: "LIV", homeName: "Man Utd",
                           awayName: "Liverpool", kickoff: .now.addingTimeInterval(7200)),
        ]
        let data = SummaryData(
            type: .fixtures, mode: .named, leagueName: "England — Premier League",
            appName: "Last Man Standing", gameName: "The Office Pool", roundNumber: 3,
            timestampLabel: "Picks due · Sat 16 Aug · 12:30", pickGroups: [],
            survivors: [], eliminated: [], managerSurvived: false, managerEliminated: false,
            outcome: nil, outcomePlayers: [], fixtures: fx, activeCount: 10, eliminatedCount: 2)
        #expect(renders(data))
    }
}
