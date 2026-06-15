import SwiftUI

/// Manager override (spec §13c.8): declare winner(s) at any round close. Selected
/// players become winners, everyone else is eliminated, and the game completes —
/// regardless of the configured tie rule.
struct DeclareWinnersView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let onDone: () -> Void

    @State private var selection: Set<UUID> = []

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Select the winner(s)") {
                    ForEach(sortedPlayers, id: \.id) { player in
                        Button {
                            toggle(player.id)
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.primary)
                                if player.status != .active {
                                    Text(player.status.rawValue.capitalized)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.contains(player.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("Selected players win; everyone else is eliminated and the game ends.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Declare Winner(s)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Declare") { apply() }.disabled(selection.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func apply() {
        GameLogicService.apply(.winners(Array(selection)), game: game)
        onDone()
        dismiss()
    }
}
