import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// A subscription's billing length. Monthly only for now (no annual option on
/// any tier) — kept as an enum, not collapsed away, so adding an annual option
/// to a tier later is a RevenueCat + `PurchaseOption.all` change, not a rename.
enum BillingPeriod: String {
    case monthly
    case annual
}

/// One purchasable package: a tier + billing length. Maps to a RevenueCat
/// package identifier — `"<tier>"` for No Ads (it will never have an annual
/// option, so no suffix is needed), `"<tier>_<period>"` for everything else
/// (suffixed even though only monthly exists today, e.g. "leagues_3_monthly",
/// so adding annual later is a RevenueCat-only change, no app-side rename).
/// Multiple options can share a `Tier` (and so the same RevenueCat
/// entitlement) — purchasing either grants the same access.
struct PurchaseOption: Identifiable, Hashable {
    let tier: Tier
    let period: BillingPeriod

    var id: String { packageId }
    var packageId: String {
        tier == .noAds ? tier.rawValue : "\(tier.rawValue)_\(period.rawValue)"
    }

    /// Every package the paywall can offer, in display order. Add a new
    /// duration for a tier here only — no other code needs to change.
    static let all: [PurchaseOption] = [
        PurchaseOption(tier: .noAds, period: .monthly),
        PurchaseOption(tier: .leagues3, period: .monthly),
        PurchaseOption(tier: .leagues5, period: .monthly),
        PurchaseOption(tier: .leagues7, period: .monthly),
    ]
}

/// RevenueCat wrapper. Compiles with or without the SDK present (guarded by
/// `canImport`), so the build stays green until the `purchases-ios` package is
/// added in Xcode. Until a real API key is set, the app runs on the dev tier
/// override (Settings) — exactly the with/without-ads testing flow.
@MainActor
final class PurchaseService {
    static let shared = PurchaseService()

    private static let apiKey = "appl_YzVhdARQYOPkfOeQpGuvTkvNTeA"

    private(set) var isConfigured = false

    private init() {}

    /// The result of a restore or purchase, so the UI can always tell the user
    /// what happened (never a silent no-op). `.unavailable` covers the pre-release
    /// state where RevenueCat isn't linked / no key is set yet.
    enum PurchaseOutcome {
        case success(Tier)
        case cancelled
        case failed(String)
        case unavailable
    }

    /// Call once at launch. No-ops if the SDK isn't linked or the key is unset.
    func configure() {
        #if canImport(RevenueCat)
        guard !isConfigured, !Self.apiKey.contains("REPLACE_ME") else { return }
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: Self.apiKey)
        isConfigured = true
        Task { await refreshTier() }
        #endif
    }

    func refreshTier() async {
        #if canImport(RevenueCat)
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            Entitlements.shared.apply(tier: Self.tier(from: info))
        } catch {
            // Leave the current tier; a later refresh (foreground) can retry.
        }
        #endif
    }

    /// Restore previous purchases, reporting the outcome so the UI can confirm
    /// success or surface a failure (no more silent no-op).
    func restore() async -> PurchaseOutcome {
        #if canImport(RevenueCat)
        guard isConfigured else { return .unavailable }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let tier = Self.tier(from: info)
            Entitlements.shared.apply(tier: tier)
            return .success(tier)
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    /// Buy `option` (a tier + billing length), reporting the outcome.
    func purchase(_ option: PurchaseOption) async -> PurchaseOutcome {
        #if canImport(RevenueCat)
        guard isConfigured else { return .unavailable }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let package = Self.package(for: option, in: offerings) else { return .unavailable }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            let newTier = Self.tier(from: result.customerInfo)
            Entitlements.shared.apply(tier: newTier)
            return .success(newTier)
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    #if canImport(RevenueCat)
    private static func tier(from info: CustomerInfo) -> Tier {
        if info.entitlements[Entitlements.entitlementLeagues7]?.isActive == true { return .leagues7 }
        if info.entitlements[Entitlements.entitlementLeagues5]?.isActive == true { return .leagues5 }
        if info.entitlements[Entitlements.entitlementLeagues3]?.isActive == true { return .leagues3 }
        if info.entitlements[Entitlements.entitlementNoAds]?.isActive == true { return .noAds }
        return .free
    }

    /// Maps a purchase option to its RevenueCat package by `packageId`. TODO:
    /// confirm these identifiers in the RevenueCat dashboard match
    /// `PurchaseOption.packageId` (e.g. "no_ads", "leagues_3_monthly",
    /// "leagues_5_monthly", "leagues_7_monthly").
    private static func package(for option: PurchaseOption, in offerings: Offerings) -> Package? {
        let packages = offerings.current?.availablePackages ?? []
        return packages.first { $0.identifier == option.packageId }
    }
    #endif

    /// Localized price string for a purchase option (e.g. "£2.49"), or nil if
    /// RevenueCat isn't linked/configured or the package isn't found. This is
    /// how regional pricing reaches the UI — the price is never hardcoded in
    /// the app; it's whatever App Store Connect is showing the user's actual
    /// storefront, read back via StoreKit/RevenueCat at runtime.
    func localizedPrice(for option: PurchaseOption) async -> String? {
        #if canImport(RevenueCat)
        guard isConfigured else { return nil }
        guard let offerings = try? await Purchases.shared.offerings() else { return nil }
        guard let package = Self.package(for: option, in: offerings) else { return nil }
        return package.storeProduct.localizedPriceString
        #else
        return nil
        #endif
    }
}

extension PurchaseService.PurchaseOutcome {
    /// A user-facing alert for the outcome, or `nil` when nothing should show
    /// (the user cancelled the App Store sheet themselves). `restoring` tailors
    /// the copy for Restore vs. a fresh purchase.
    func alert(restoring: Bool) -> (title: String, message: String)? {
        switch self {
        case .success(let tier):
            if restoring && tier == .free {
                return (AppString("Nothing to restore"),
                        AppString("We couldn't find an active subscription on your Apple ID."))
            }
            return (restoring ? AppString("Purchases restored") : AppString("You're subscribed"),
                    AppString("Your \(tier.label) plan is now active."))
        case .cancelled:
            return nil
        case .failed(let message):
            return (restoring ? AppString("Restore failed") : AppString("Purchase failed"), message)
        case .unavailable:
            return (AppString("Not available yet"),
                    AppString("Subscriptions aren't available in this build yet. Please check back after the next update."))
        }
    }
}

/// Identifiable wrapper so views can drive an `.alert(item:)` from a purchase or
/// restore outcome.
struct PurchaseAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
