import SwiftUI

/// The in-app upgrade screen — the path the Settings "Upgrade" copy now leads to.
/// Lists the paid tiers with a Subscribe button each, plus Restore, and always
/// reports the outcome (success / failure / unavailable) via an alert so a tap is
/// never a silent no-op. Until RevenueCat is linked + a real key is set, purchases
/// resolve to `.unavailable` and the user is told so, rather than nothing happening.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    /// The tier whose button is mid-flight (drives the spinner + disables input).
    @State private var working: Tier?
    @State private var alert: PurchaseAlertItem?
    /// Localized price strings fetched from RevenueCat/StoreKit — never
    /// hardcoded, so each user sees their own storefront's price (e.g. £2.49
    /// in the UK, €2.99 in the Eurozone) without any region logic in the app.
    @State private var prices: [Tier: String] = [:]

    private let paidTiers: [Tier] = [.noAds, .threeLeague, .unlimited]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(paidTiers) { tier in
                        tierRow(tier)
                    }
                } header: {
                    Text("Choose a plan")
                } footer: {
                    Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in the App Store under your Apple ID → Subscriptions.")
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await runRestore() }
                    }
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
        for tier in paidTiers {
            if let price = await PurchaseService.shared.localizedPrice(for: tier) {
                prices[tier] = price
            }
        }
    }

    @ViewBuilder
    private func tierRow(_ tier: Tier) -> some View {
        let isCurrent = entitlements.tier == tier
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tier.label).font(.headline)
                if let price = prices[tier] {
                    Text("· \(price)/mo").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text("Current").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Subscribe") { Task { await runPurchase(tier) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(tier.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func runPurchase(_ tier: Tier) async {
        working = tier
        let outcome = await PurchaseService.shared.purchase(tier)
        working = nil
        present(outcome, restoring: false)
    }

    private func runRestore() async {
        working = .free   // any non-nil value flags "busy"
        let outcome = await PurchaseService.shared.restore()
        working = nil
        present(outcome, restoring: true)
    }

    private func present(_ outcome: PurchaseService.PurchaseOutcome, restoring: Bool) {
        guard let a = outcome.alert(restoring: restoring) else { return }
        alert = PurchaseAlertItem(title: a.title, message: a.message)
    }
}
