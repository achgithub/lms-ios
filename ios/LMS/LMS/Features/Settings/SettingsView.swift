import SwiftUI
import SwiftData
import StoreKit

/// Settings (spec §7.2). The League section is a checklist of the leagues the
/// user has enabled (capped by their subscription). Disabling a league removes
/// its on-device data and deletes any game that uses it — guarded by a two-step
/// confirmation.
struct SettingsView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Environment(Entitlements.self) private var entitlements
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]

    // Two-step confirmation for disabling a league.
    @State private var pendingDisable: LeagueOption?   // first warning
    @State private var confirmDisable: LeagueOption?   // second (final) warning
    // Single-league plans swap their one league instead of disable/enable.
    @State private var pendingSwap: LeagueOption?
    // Upgrade / restore.
    @State private var showPaywall = false
    @State private var purchaseAlert: PurchaseAlertItem?
    #if DEBUG
    @State private var storeKitDiagnostic: String?
    #endif

    private var allowance: Int { entitlements.leagueAllowance }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { localization.language }, set: { localization.select($0) })
    }

    /// Games that reference a league (whole game is deleted, even if it blends
    /// other leagues too).
    private func gamesUsing(_ league: LeagueOption) -> [Game] {
        games.filter { $0.leagues.contains(league) }
    }

    #if DEBUG
    private var tierBinding: Binding<Tier> {
        Binding(get: { entitlements.tier }, set: { entitlements.setDevTier($0) })
    }
    #endif

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
                    if entitlements.tier != .leagues7 {
                        Button("Upgrade") { showPaywall = true }
                    }
                    Button("Restore Purchases") {
                        Task {
                            let outcome = await PurchaseService.shared.restore()
                            if let a = outcome.alert(restoring: true) {
                                purchaseAlert = PurchaseAlertItem(title: a.title, message: a.message)
                            }
                        }
                    }
                }

                #if DEBUG
                Section("Developer (testing)") {
                    Picker("Simulate tier", selection: tierBinding) {
                        ForEach(Tier.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Flips ad-on / ad-off + league allowance without a purchase. Free/No Ads = 1, then 3 / 5 / 7 leagues by tier.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Check StoreKit Products (bypass RevenueCat)") {
                        Task {
                            let ids = Set(PurchaseOption.all.map { $0.packageId })
                            do {
                                let products = try await Product.products(for: ids)
                                let found = Set(products.map { $0.id })
                                let missing = ids.subtracting(found)
                                storeKitDiagnostic = "Found \(products.count)/\(ids.count): \(found.sorted().joined(separator: ", "))\nMissing: \(missing.isEmpty ? "none" : missing.sorted().joined(separator: ", "))"
                            } catch {
                                storeKitDiagnostic = "Error: \(error)"
                            }
                        }
                    }
                    if let diagnostic = storeKitDiagnostic {
                        Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                    }
                }
                #endif

                leagueSection

                Section {
                    Picker("Language", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            // Endonym (e.g. "Deutsch") — fixed, never translated.
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose the app's language. Team, player and league names always come from the league data.")
                        // Deliberately English-only (verbatim) so the disclaimer
                        // reads the same in every language.
                        Text(verbatim: "Translations are AI-assisted — please report any errors.")
                    }
                }

                Section {
                    LabeledContent("App", value: Leagues.app.name)
                    LabeledContent("Version", value: version)
                    // Attribution required by the football-data.org licence: a
                    // visible "Data provided by football-data.org" credit. Brand
                    // name kept verbatim so it reads identically in every language.
                    Link(destination: URL(string: "https://www.football-data.org")!) {
                        Text(verbatim: "Data provided by football-data.org")
                    }
                    Link("Privacy Policy", destination: URL(string: "https://sportsmanager-site.pages.dev/lsm/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://sportsmanager-site.pages.dev/lsm/terms")!)
                    // Apple requires a link to its standard EULA (or a custom one
                    // containing Apple's mandated minimum terms — ours above
                    // doesn't) since subscriptions are sold via In-App Purchase.
                    // Keep this alongside our own terms.html, not instead of it.
                    Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                } header: {
                    Text("About")
                } footer: {
                    // Single localized string key — can't wrap without changing the key.
                    // swiftlint:disable:next line_length
                    Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                }
            }
            .appBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView().environment(entitlements)
            }
            .alert(item: $purchaseAlert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
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
                Text(verbatim: disableMessage(league))
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
                Text(verbatim: n == 1
                     ? AppString("This permanently deletes 1 game and can't be undone.")
                     : AppString("This permanently deletes \(n) games and can't be undone."))
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
                Text(verbatim: switchMessage(to: target))
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
            Text(verbatim: leagueFooter)
        }
    }

    /// League-section footer: a base sentence plus an optional "subscribe" nudge
    /// when the catalogue has more leagues than the plan allows. Built in Swift so
    /// each clause is a clean, fully-translatable sentence (no inline plurals).
    private var leagueFooter: String {
        let canSubscribeForMore = allowance < Leagues.all.count
        if allowance == 1 {
            var text = AppString("Your \(entitlements.tier.label) plan includes 1 league — tap another to switch.")
            if canSubscribeForMore { text += " " + AppString("Subscribe to run more at once.") }
            return text
        } else {
            var text = AppString("You can enable \(allowance) leagues on the \(entitlements.tier.label) plan.")
            if canSubscribeForMore { text += " " + AppString("Subscribe to enable more.") }
            return text
        }
    }

    /// First disable-confirm message — singular / plural / no-games variants.
    private func disableMessage(_ league: LeagueOption) -> String {
        let n = gamesUsing(league).count
        switch n {
        case 0:  return AppString("Disabling \(league.name) removes its data from this device.")
        case 1:  return AppString("Disabling \(league.name) removes its data from this device and deletes 1 game that uses it.")
        default: return AppString("Disabling \(league.name) removes its data from this device and deletes \(n) games that use it.")
        }
    }

    /// Single-league-plan swap-confirm message — singular / plural / no-games.
    private func switchMessage(to target: LeagueOption) -> String {
        let current = enabled.leagues.first?.name ?? AppString("your league")
        let n = enabled.leagues.reduce(0) { $0 + gamesUsing($1).count }
        switch n {
        case 0:  return AppString("Switches from \(current) to \(target.name).")
        case 1:  return AppString("Switches from \(current) to \(target.name), deleting 1 game that uses the old league.")
        default: return AppString("Switches from \(current) to \(target.name), deleting \(n) games that use the old league.")
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
