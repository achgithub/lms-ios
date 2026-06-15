import SwiftUI
import SwiftData

/// Create-game form (spec §6.1). Anonymity and tie rule are set once here and
/// can't change mid-season.
struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(EnabledLeagues.self) private var enabled
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var name = ""
    @State private var season = LeagueConfig.shared.season
    @State private var allowRepeats = LeagueConfig.shared.allowRepeatDefault
    @State private var tieRule: TieRule = LeagueConfig.shared.defaultTieRule
    @State private var anonymity: AnonymityMode = .named
    @State private var selectedLeagueIds: Set<String> = []
    @State private var managerPlaying = true   // manager opts in/out per game

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty && !selectedLeagueIds.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    TextField("Game name", text: $name)
                    LabeledContent("Season", value: season)
                }

                Section {
                    if enabled.leagues.count == 1 {
                        LabeledContent("League", value: enabled.leagues[0].name)
                    } else {
                        ForEach(enabled.leagues) { league in
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
                    Text("League\(enabled.leagues.count > 1 ? "s" : "")")
                } footer: {
                    if enabled.leagues.count > 1 {
                        Text("Pick one league, or blend several — players can then pick teams from any of them.")
                    }
                }

                Section("Rules") {
                    Toggle("Allow team repeats", isOn: $allowRepeats)

                    Picker("Tie / all-eliminated", selection: $tieRule) {
                        ForEach(TieRule.allCases) { Text($0.label).tag($0) }
                    }
                    Text(tieRule.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            // Default to all enabled leagues when there's one; else preselect the
            // first so a single-league game is the zero-tap default.
            .onAppear {
                if selectedLeagueIds.isEmpty {
                    selectedLeagueIds = enabled.leagues.count == 1
                        ? Set(enabled.leagues.map(\.id))
                        : Set(enabled.leagues.prefix(1).map(\.id))
                }
            }
        }
    }

    private func toggleLeague(_ id: String) {
        if selectedLeagueIds.contains(id) { selectedLeagueIds.remove(id) } else { selectedLeagueIds.insert(id) }
    }

    private func create() {
        let game = Game(
            name: trimmedName,
            season: season,
            allowRepeats: allowRepeats,
            tieRule: tieRule,
            anonymityMode: anonymity,
            leagueIds: Array(selectedLeagueIds)
        )
        context.insert(game)

        // The manager plays only if they opted in (they may run games they don't
        // play in — no ⚑ then). Can still add/remove themselves later in the game.
        if managerPlaying && !managerTrimmed.isEmpty {
            let player = Player(name: managerTrimmed, game: game, isManager: true)
            context.insert(player)
            game.players.append(player)
        }
        dismiss()
    }
}
