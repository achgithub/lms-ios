import SwiftUI
import SwiftData

/// Shown full-screen and non-dismissable when the user has more leagues enabled
/// than their subscription allows (e.g. a cancelled/downgraded plan). The app is
/// blocked until they reduce to the allowance — they choose which league(s) to
/// keep here. Removing a league deletes any game that uses it (same rule as the
/// Settings checklist). Auto-dismisses (via the parent) once within allowance.
struct LeagueDowngradeView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    @State private var pendingRemove: LeagueOption?

    private var allowance: Int { entitlements.leagueAllowance }
    private var overBy: Int { max(0, enabled.ids.count - allowance) }

    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Your plan now includes \(allowance) league\(allowance == 1 ? "" : "s"). You have \(enabled.ids.count) enabled — remove \(overBy) to continue.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }

                Section("Keep one — remove the rest") {
                    ForEach(enabled.leagues) { league in
                        HStack {
                            Text(league.name)
                            Spacer()
                            Button("Remove", role: .destructive) { pendingRemove = league }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await PurchaseService.shared.restore() }
                    }
                } footer: {
                    Text("Renewed by mistake? Restore your subscription to keep all your leagues.")
                }
            }
            .navigationTitle("Choose your league\(allowance == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .confirmationDialog(
                "Remove \(pendingRemove?.name ?? "")?",
                isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemove
            ) { league in
                Button("Remove & delete games", role: .destructive) { remove(league) }
                Button("Cancel", role: .cancel) {}
            } message: { league in
                let n = gamesUsing(league).count
                Text("Removes \(league.name) from this device\(n > 0 ? " and permanently deletes \(n) game\(n == 1 ? "" : "s") that use it" : "").")
            }
        }
    }

    private func remove(_ league: LeagueOption) {
        for game in gamesUsing(league) { context.delete(game) }
        enabled.disable(league)
        pendingRemove = nil
    }
}
