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
    @State private var searchText = ""
    @State private var unassignedOnly = false

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

    /// Active players after the unassigned-only filter and name search — so a
    /// manager with hundreds of players can find the stragglers fast.
    private var filteredPlayers: [Player] {
        activePlayers.filter { player in
            (!unassignedOnly || GameLogicService.pick(for: player, in: round) == nil)
                && (searchText.isEmpty || player.name.localizedCaseInsensitiveContains(searchText))
        }
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
                        Section {
                            Picker("Show", selection: $unassignedOnly) {
                                Text("All (\(activePlayers.count))").tag(false)
                                Text("Unassigned (\(unpickedCount))").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }

                        Section {
                            if filteredPlayers.isEmpty {
                                Text(unassignedOnly ? "Everyone's assigned." : "No players match.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredPlayers) { player in
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
                    .searchable(text: $searchText, prompt: "Search players")
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
                    // Ad gates opening the card so it can't be screenshot ad-free.
                    Button { AdGate.run { showShare = true } } label: {
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
                unpickedCount == 1
                    ? AppString("Auto-assign 1 player?")
                    : AppString("Auto-assign \(unpickedCount) players?"),
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

    @State private var showPicker = false

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
        // A plain button opening a sheet — avoids the iOS Menu collapse animation
        // that staged the tile + name in two passes after a selection.
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(player.name).foregroundStyle(.primary)
                Spacer()
                if let currentPick {
                    Text(teamsById[currentPick.teamId]?.shortName ?? "Team \(currentPick.teamId)")
                        .foregroundStyle(.primary)
                } else {
                    Text("Assign").foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            TeamPickSheet(
                playerName: player.name,
                eligible: eligible,
                currentTeamId: currentPick?.teamId,
                teamsById: teamsById,
                onSelect: { teamId in
                    GameLogicService.setPick(player: player, round: round, teamId: teamId, context: context)
                    showPicker = false
                },
                onClear: currentPick == nil ? nil : {
                    GameLogicService.clearPick(player: player, round: round, context: context)
                    showPicker = false
                }
            )
        }
    }
}

/// Team picker for one player — a tappable list of eligible teams with tiles.
private struct TeamPickSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playerName: String
    let eligible: [TeamRef]
    let currentTeamId: Int?
    let teamsById: [Int: TeamDTO]
    let onSelect: (Int) -> Void
    let onClear: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if let onClear {
                    Section {
                        Button(role: .destructive) { onClear() } label: {
                            Label("Clear pick", systemImage: "xmark.circle")
                        }
                    }
                }
                Section {
                    ForEach(eligible, id: \.id) { team in
                        Button {
                            onSelect(team.id)
                        } label: {
                            HStack(spacing: 10) {
                                Text(team.name).foregroundStyle(.primary)
                                Spacer()
                                if team.id == currentTeamId {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(playerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
