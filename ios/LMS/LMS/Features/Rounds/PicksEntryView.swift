import SwiftUI
import SwiftData

/// Manager picks-entry for the current round: per-player eligible-team picker
/// plus engine auto-assign (§6.4, §7.2). Picks are saved as they're chosen.
struct PicksEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAutoAssignConfirm = false
    @State private var showShare = false

    private var teamRefs: [TeamRef] {
        guard let data else { return [] }
        return GameLogicService.teamRefs(
            forFixtureIds: round.fixtureIds,
            fixtures: data.fixtures,
            teamsById: data.teamsById,
            standingsByTeam: data.standingsByTeam
        )
    }

    private var activePlayers: [Player] {
        game.players.filter { $0.status == .active }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unpickedCount: Int {
        activePlayers.filter { GameLogicService.pick(for: $0, in: round) == nil }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading teams…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load teams", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if activePlayers.isEmpty {
                    ContentUnavailableView("No active players", systemImage: "person.slash")
                } else {
                    List {
                        ForEach(activePlayers) { player in
                            PlayerPickRow(
                                player: player,
                                round: round,
                                teamRefs: teamRefs,
                                allowRepeats: game.allowRepeats,
                                teamsById: data?.teamsById ?? [:]
                            )
                        }
                    }
                }
            }
            .navigationTitle("Picks · Round \(round.roundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Auto-Assign") { showAutoAssignConfirm = true }
                        .disabled(teamRefs.isEmpty || unpickedCount == 0)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(round.picks.isEmpty)
                }
            }
            .task { await load() }
            .sheet(isPresented: $showShare) {
                SummaryShareView(game: game, round: round, type: .picks)
            }
            .confirmationDialog(
                "Auto-assign \(unpickedCount) player\(unpickedCount == 1 ? "" : "s")?",
                isPresented: $showAutoAssignConfirm,
                titleVisibility: .visible
            ) {
                Button("Auto-Assign") { runAutoAssign() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each unassigned player gets the bottom-of-table team still available to them.")
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: game.leagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func runAutoAssign() {
        let proposals = GameLogicService.proposeAutoAssign(round: round, game: game, teamRefs: teamRefs)
        for proposal in proposals {
            GameLogicService.setPick(player: proposal.player, round: round, teamId: proposal.teamId, context: context)
        }
    }
}

private struct PlayerPickRow: View {
    @Environment(\.modelContext) private var context
    let player: Player
    let round: Round
    let teamRefs: [TeamRef]
    let allowRepeats: Bool
    let teamsById: [Int: TeamDTO]

    private var eligible: [TeamRef] {
        let standingsKnown = teamRefs.contains { $0.position != nil }
        return GameEngine.orderedAvailableTeams(
            fixtureTeams: teamRefs,
            used: GameLogicService.usedTeamIds(for: player),
            allowRepeats: allowRepeats,
            standingsKnown: standingsKnown
        )
    }

    private var currentPick: Pick? { GameLogicService.pick(for: player, in: round) }

    var body: some View {
        HStack {
            Text(player.name)
            Spacer()
            Menu {
                if currentPick != nil {
                    Button(role: .destructive) {
                        GameLogicService.clearPick(player: player, round: round, context: context)
                    } label: {
                        Label("Clear pick", systemImage: "xmark.circle")
                    }
                    Divider()
                }
                ForEach(eligible, id: \.id) { team in
                    Button {
                        GameLogicService.setPick(player: player, round: round, teamId: team.id, context: context)
                    } label: {
                        if team.id == currentPick?.teamId {
                            Label(team.name, systemImage: "checkmark")
                        } else {
                            Text(team.name)
                        }
                    }
                }
            } label: {
                if let currentPick {
                    HStack(spacing: 6) {
                        TeamTile(tla: teamsById[currentPick.teamId]?.tla, size: .small)
                        Text(teamsById[currentPick.teamId]?.shortName ?? "Team \(currentPick.teamId)")
                    }
                } else {
                    Text("Assign").foregroundStyle(.blue)
                }
            }
        }
    }
}
