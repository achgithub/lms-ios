import SwiftUI
import SwiftData

/// Create-game form (spec §6.1). Anonymity is set once here and can't change
/// mid-season. Tie / all-eliminated outcomes are chosen in the moment when they
/// actually arise (see `TieResolutionView`), not pre-committed at creation.
struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(EnabledLeagues.self) private var enabled
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var name = ""
    @State private var season = Leagues.app.season
    @State private var anonymity: AnonymityMode = .anonymous
    @State private var selectedLeagueIds: Set<String> = []
    @State private var managerPlaying = true   // manager opts in/out per game
    @State private var drawEliminates = true
    @State private var postponedEliminates = false

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty && !selectedLeagueIds.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    TextField("Game name", text: $name)
                }

                // Always shown so the manager can always see which league(s) a game
                // will use. A single-league setup shows that one league greyed out
                // (nothing to choose); 2+ leagues is an interactive, forced choice —
                // none pre-ticked, so a manager never silently blends leagues they
                // didn't mean to.
                Section {
                    ForEach(enabled.leagues) { league in
                        if enabled.leagues.count == 1 {
                            HStack {
                                Text(league.name).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                toggleLeague(league.id)
                            } label: {
                                HStack {
                                    Text(league.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedLeagueIds.contains(league.id) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Leagues")
                } footer: {
                    Text(enabled.leagues.count == 1
                         ? "Your only enabled league. Enable more in Settings to blend leagues in a game."
                         : "Pick one league, or blend several — players can then pick teams from any of them.")
                }

                if !managerTrimmed.isEmpty {
                    Section {
                        Button {
                            managerPlaying.toggle()
                        } label: {
                            HStack {
                                Text("\(managerTrimmed) (you)").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: managerPlaying ? "minus.circle.fill" : "plus.circle")
                                    .foregroundStyle(managerPlaying ? .red : .blue)
                            }
                        }
                    } header: {
                        Text("You")
                    } footer: {
                        Text(managerPlaying
                             ? "You're playing in this game — your pick shows on shared cards (⚑)."
                             : "You're running this game but not playing — no ⚑ on cards.")
                    }
                }

                Section {
                    HStack {
                        Text("Win").foregroundStyle(.secondary)
                        Spacer()
                        Text("Survives").foregroundStyle(.secondary)
                    }
                    Toggle(isOn: $postponedEliminates) {
                        resultRuleLabel("Postponed", eliminates: postponedEliminates)
                    }
                    Toggle(isOn: $drawEliminates) {
                        resultRuleLabel("Draw", eliminates: drawEliminates)
                    }
                    HStack {
                        Text("Loss").foregroundStyle(.secondary)
                        Spacer()
                        Text("Eliminates").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Result Rules")
                } footer: {
                    Text("A win always survives and a loss always eliminates. Toggle on for Postponed/Draw to treat them as a loss too — off keeps them as a survive.")
                }

                Section("Summaries") {
                    Picker("Anonymity", selection: $anonymity) {
                        ForEach(AnonymityMode.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            // Single-league setup: zero-tap default (nothing to choose). 2+
            // leagues: no default tick at all — the manager must explicitly
            // choose, so a game is never created with a league they didn't mean
            // to include (see the Leagues section above).
            .onAppear {
                if selectedLeagueIds.isEmpty, enabled.leagues.count == 1 {
                    selectedLeagueIds = Set(enabled.leagues.map(\.id))
                }
            }
        }
    }

    private func resultRuleLabel(_ title: LocalizedStringKey, eliminates: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            Text(eliminates ? "Counts as a loss" : "Counts as a win")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) { selectedLeagueIds.remove(id) } else { selectedLeagueIds.insert(id) }
    }

    private func create() {
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: Leagues.app.allowRepeatDefault,
            anonymityMode: anonymity,
            leagueIds: Array(selectedLeagueIds),
            drawEliminates: drawEliminates,
            postponedEliminates: postponedEliminates
        )
        context.insert(game)

        // The manager plays only if they opted in (they may run games they don't
        // play in — no ⚑ then). Can still add/remove themselves later in the game.
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true,
                                entryNumber: game.nextEntryNumber)
            context.insert(player)
            game.players.append(player)
        }
        dismiss()
    }
}
