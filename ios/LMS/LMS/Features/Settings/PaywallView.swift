import SwiftUI

/// The in-app upgrade screen — the path the Settings "Upgrade" copy now leads to.
/// One section per paid tier (No Ads, 3 Leagues, 5 Leagues, 7 Leagues), each
/// listing its purchasable `PurchaseOption`s (monthly only, no annual yet) with
/// a Subscribe button, plus Restore. Always reports the outcome (success /
/// failure / unavailable) via an alert so a tap is never a silent no-op. Until
/// RevenueCat is linked + a real key is set, purchases resolve to `.unavailable`
/// and the user is told so, rather than nothing happening.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    /// The option whose button is mid-flight (drives the spinner + disables input).
    @State private var working: PurchaseOption?
    @State private var alert: PurchaseAlertItem?
    /// Localized price strings fetched from RevenueCat/StoreKit — never
    /// hardcoded, so each user sees their own storefront's price (e.g. £2.49
    /// in the UK, €2.99 in the Eurozone) without any region logic in the app.
    @State private var prices: [PurchaseOption: String] = [:]

    private let paidTiers: [Tier] = [.noAds, .leagues3, .leagues5, .leagues7]

    private func options(for tier: Tier) -> [PurchaseOption] {
        PurchaseOption.all.filter { $0.tier == tier }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(paidTiers) { tier in
                    Section {
                        ForEach(options(for: tier)) { option in
                            optionRow(option, showsPeriod: options(for: tier).count > 1)
                        }
                    } header: {
                        Text(tier.label)
                    } footer: {
                        Text(tier.detail)
                    }
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await runRestore() }
                    }
                } footer: {
                    Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in the App Store under your Apple ID → Subscriptions.")
                }

                Section {
                    // Required by App Store Review Guideline 3.1.2 — functional links to
                    // the Terms of Use (Apple's standard EULA) and Privacy Policy must be
                    // present on or reachable from the purchase screen.
                    Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Privacy Policy", destination: URL(string: "https://sportsmanager-site.pages.dev/lsm/privacy")!)
                }
            }
            .navigationTitle("Go Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .disabled(working != nil)
            .overlay {
                if working != nil { ProgressView().controlSize(.large) }
            }
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
            .task { await loadPrices() }
        }
    }

    private func loadPrices() async {
        for option in PurchaseOption.all {
            if let price = await PurchaseService.shared.localizedPrice(for: option) {
                prices[option] = price
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: PurchaseOption, showsPeriod: Bool) -> some View {
        let isCurrent = entitlements.tier == option.tier
        HStack {
            if showsPeriod {
                Text(option.period == .annual ? "Annual" : "Monthly")
            }
            if let price = prices[option] {
                Text(price).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Text("Current").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Subscribe") { Task { await runPurchase(option) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func runPurchase(_ option: PurchaseOption) async {
        working = option
        let outcome = await PurchaseService.shared.purchase(option)
        working = nil
        present(outcome, restoring: false)
    }

    private func runRestore() async {
        working = PurchaseOption(tier: .noAds, period: .monthly)   // any non-nil value flags "busy"
        let outcome = await PurchaseService.shared.restore()
        working = nil
        present(outcome, restoring: true)
    }

    private func present(_ outcome: PurchaseService.PurchaseOutcome, restoring: Bool) {
        guard let a = outcome.alert(restoring: restoring) else { return }
        alert = PurchaseAlertItem(title: a.title, message: a.message)
    }
}
