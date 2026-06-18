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
    @State private var purchaseAlert: PurchaseAlertItem?

    private var allowance: Int { entitlements.leagueAllowance }
    private var overBy: Int { max(0, enabled.ids.count - allowance) }

    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    /// The "you're over your allowance" banner — singular / plural on the allowance.
    private var overLimitMessage: String {
        allowance == 1
            ? AppString("Your plan now includes 1 league. You have \(enabled.ids.count) enabled — remove \(overBy) to continue.")
            : AppString("Your plan now includes \(allowance) leagues. You have \(enabled.ids.count) enabled — remove \(overBy) to continue.")
    }

    /// Remove-confirm message — singular / plural / no-games variants.
    private func removeMessage(_ league: LeagueOption) -> String {
        let n = gamesUsing(league).count
        switch n {
        case 0:  return AppString("Removes \(league.name) from this device.")
        case 1:  return AppString("Removes \(league.name) from this device and permanently deletes 1 game that uses it.")
        default: return AppString("Removes \(league.name) from this device and permanently deletes \(n) games that use it.")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(verbatim: overLimitMessage)
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
                        Task {
                            let outcome = await PurchaseService.shared.restore()
                            if let a = outcome.alert(restoring: true) {
                                purchaseAlert = PurchaseAlertItem(title: a.title, message: a.message)
                            }
                        }
                    }
                } footer: {
                    Text("Renewed by mistake? Restore your subscription to keep all your leagues.")
                }

                #if DEBUG
                Section {
                    Button("Simulate Unlimited (testing)") { entitlements.setDevTier(.unlimited) }
                } footer: {
                    Text("Dev only: unlock all leagues without a purchase (persists across rebuilds).")
                }
                #endif
            }
            .navigationTitle(allowance == 1
                             ? AppString("Choose your league")
                             : AppString("Choose your leagues"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .alert(item: $purchaseAlert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                "Remove \(pendingRemove?.name ?? "")?",
                isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemove
            ) { league in
                Button("Remove & delete games", role: .destructive) { remove(league) }
                Button("Cancel", role: .cancel) {}
            } message: { league in
                Text(verbatim: removeMessage(league))
            }
        }
    }

    private func remove(_ league: LeagueOption) {
        for game in gamesUsing(league) { context.delete(game) }
        enabled.disable(league)
        pendingRemove = nil
    }
}
