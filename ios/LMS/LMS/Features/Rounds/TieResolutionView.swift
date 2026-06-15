import SwiftUI

/// Shown when everyone still active was eliminated in the same round (§13c.4) —
/// "more than one go out on the last round." The manager picks the resolution in
/// the moment: split the win, roll the week for the tied players, or bring
/// everyone back in. (A manual winner declaration lives in `DeclareWinnersView`.)
struct TieResolutionView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let tiedPlayers: [Player]
    /// True when the tied group has used every team in the league(s), so a
    /// roll-the-week must reopen their pool. Computed by the caller (it has the
    /// loaded team data).
    let poolExhausted: Bool
    /// Reports the resolution: a follow-up round type (`.rollover`) to open next,
    /// or `nil` when the game is now complete.
    let onResolved: (RoundType?) -> Void

    private var tiedIds: [UUID] { tiedPlayers.map(\.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Everyone still in was eliminated this round — no clear winner. How should it resolve?")
                        .font(.subheadline)
                }

                Section {
                    Button {
                        resolve(.winners(tiedIds))
                    } label: {
                        actionLabel("Split the win", "Joint winners — the prize is divided.")
                    }

                    Button {
                        resolve(.rollWeek(tiedIds: tiedIds, resetPool: poolExhausted))
                    } label: {
                        actionLabel("Roll the week", rollDetail)
                    }

                    Button {
                        resolve(.everyoneBackIn(allIds: game.players.map(\.id)))
                    } label: {
                        actionLabel("Everyone back in", "All \(game.players.count) players reinstated, picks reset.")
                    }
                }
            }
            .navigationTitle("No Clear Winner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
        .interactiveDismissDisabled()
    }

    private var rollDetail: String {
        let base = "The \(tiedPlayers.count) tied players carry forward and replay."
        return poolExhausted ? base + " Their team pool resets — all teams open again." : base
    }

    private func actionLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resolve(_ outcome: TieOutcome) {
        let followUp = GameLogicService.apply(outcome, game: game)
        onResolved(followUp)
        dismiss()
    }
}
