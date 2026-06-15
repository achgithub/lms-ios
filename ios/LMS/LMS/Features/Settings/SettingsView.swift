import SwiftUI
import SwiftData

/// Settings (spec §7.2). The League section is a checklist of the leagues the
/// user has enabled (capped by their subscription). Disabling a league removes
/// its on-device data and deletes any game that uses it — guarded by a two-step
/// confirmation.
struct SettingsView: View {
    private let config = LeagueConfig.shared
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    // Two-step confirmation for disabling a league.
    @State private var pendingDisable: LeagueOption?   // first warning
    @State private var confirmDisable: LeagueOption?   // second (final) warning
    // Single-league plans swap their one league instead of disable/enable.
    @State private var pendingSwap: LeagueOption?

    private var allowance: Int { entitlements.leagueAllowance }

    /// Games that reference a league (whole game is deleted, even if it blends
    /// other leagues too).
    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    private var tierBinding: Binding<Tier> {
        Binding(get: { entitlements.tier }, set: { entitlements.setDevTier($0) })
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $managerName)
                        .textInputAutocapitalization(.words)
                    Text("You're added to games you create, and your pick is always shown on shared summary cards.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Subscription") {
                    LabeledContent("Plan", value: entitlements.tier.label)
                    Text(entitlements.tier.detail)
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore Purchases") {
                        Task { await PurchaseService.shared.restore() }
                    }
                }

                Section("Developer (testing)") {
                    Picker("Simulate tier", selection: tierBinding) {
                        ForEach(Tier.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Flips ad-on / ad-off + league allowance without a purchase. Free = 1 league; paid = all.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                leagueSection

                Section("About") {
                    LabeledContent("App", value: config.appName)
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Disable \(pendingDisable?.name ?? "league")?",
                isPresented: Binding(get: { pendingDisable != nil }, set: { if !$0 { pendingDisable = nil } }),
                titleVisibility: .visible,
                presenting: pendingDisable
            ) { league in
                Button("Continue", role: .destructive) {
                    pendingDisable = nil
                    confirmDisable = league
                }
                Button("Cancel", role: .cancel) {}
            } message: { league in
                let n = gamesUsing(league).count
                Text("Disabling \(league.name) removes its data from this device\(n > 0 ? " and deletes \(n) game\(n == 1 ? "" : "s") that use it" : "").")
            }
            .confirmationDialog(
                "Delete games in \(confirmDisable?.name ?? "")?",
                isPresented: Binding(get: { confirmDisable != nil }, set: { if !$0 { confirmDisable = nil } }),
                titleVisibility: .visible,
                presenting: confirmDisable
            ) { league in
                Button("Disable & delete", role: .destructive) { disable(league) }
                Button("Cancel", role: .cancel) {}
            } message: { league in
                let n = gamesUsing(league).count
                Text("This permanently deletes \(n) game\(n == 1 ? "" : "s") and can't be undone.")
            }
            .confirmationDialog(
                "Switch to \(pendingSwap?.name ?? "")?",
                isPresented: Binding(get: { pendingSwap != nil }, set: { if !$0 { pendingSwap = nil } }),
                titleVisibility: .visible,
                presenting: pendingSwap
            ) { target in
                Button("Switch", role: .destructive) { swap(to: target) }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                let current = enabled.leagues.first
                let n = enabled.leagues.reduce(0) { $0 + gamesUsing($1).count }
                Text("Switches from \(current?.name ?? "your league") to \(target.name)\(n > 0 ? ", deleting \(n) game\(n == 1 ? "" : "s") that use the old league" : "").")
            }
        }
    }

    private var leagueSection: some View {
        Section {
            ForEach(Leagues.all) { league in
                leagueRow(league)
            }
        } header: {
            Text("Leagues")
        } footer: {
            if allowance == 1 {
                Text("Your \(entitlements.tier.label) plan includes 1 league — tap another to switch.\(allowance < Leagues.all.count ? " Subscribe to run more at once." : "")")
            } else {
                Text("You can enable \(allowance) leagues on the \(entitlements.tier.label) plan.\(allowance < Leagues.all.count ? " Subscribe to enable more." : "")")
            }
        }
    }

    @ViewBuilder
    private func leagueRow(_ league: LeagueOption) -> some View {
        let isOn = enabled.isEnabled(league)
        let atCap = enabled.ids.count >= allowance
        // On a 1-league plan an unselected league is a SWAP target (tappable),
        // not locked. It's only locked when a multi-league plan is at its cap.
        let locked = !isOn && atCap && allowance > 1
        Button {
            toggle(league)
        } label: {
            HStack {
                Text(league.name).foregroundStyle(locked ? .secondary : .primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(locked)
    }

    // MARK: Toggle / disable

    private func toggle(_ league: LeagueOption) {
        if enabled.isEnabled(league) {
            guard enabled.ids.count > 1 else { return }   // keep at least one
            pendingDisable = league                        // → two-step confirm
        } else if enabled.ids.count < allowance {
            enabled.enable(league)
        } else if allowance == 1 {
            pendingSwap = league                           // swap the one league
        }
    }

    private func swap(to target: LeagueOption) {
        for current in enabled.leagues {
            for game in gamesUsing(current) { context.delete(game) }
        }
        enabled.setOnly(target)
        pendingSwap = nil
    }

    private func disable(_ league: LeagueOption) {
        for game in gamesUsing(league) { context.delete(game) }
        enabled.disable(league)
        confirmDisable = nil
    }
}
