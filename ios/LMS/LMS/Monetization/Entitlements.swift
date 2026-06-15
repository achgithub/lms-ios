import Observation

/// Subscription tiers (mirrors the darts app's TierKey / entitlement ids).
/// RevenueCat entitlement identifiers MUST match the raw values `no_ads` / `pro`.
enum Tier: String, CaseIterable, Identifiable {
    case free
    case noAds = "no_ads"
    case pro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .noAds: return "No Ads"
        case .pro: return "Pro"
        }
    }

    var detail: String {
        switch self {
        case .free: return "Ad-supported"
        case .noAds: return "Ads removed"
        case .pro: return "Ads removed + premium features"
        }
    }

    /// Both paid tiers remove ads (spec §ads / free-vs-sub tiers).
    var removesAds: Bool { self != .free }
}

/// App-wide entitlement state. In production the tier comes from RevenueCat; a
/// dev override lets you flip free / no_ads / pro on-device to test ad-on vs
/// ad-off without a real purchase (same approach as the darts EntitlementsService).
@Observable @MainActor
final class Entitlements {
    static let shared = Entitlements()

    private(set) var tier: Tier = .free
    /// True once a tier has been resolved (RevenueCat or a dev override).
    private(set) var verified = false

    // RevenueCat entitlement identifiers (match the dashboard + Tier raw values).
    static let entitlementNoAds = Tier.noAds.rawValue
    static let entitlementPro = Tier.pro.rawValue

    private init() {}

    /// The single gate the UI uses to decide whether to render ad placements.
    var shouldShowAds: Bool { !tier.removesAds }

    /// How many leagues the user may have enabled at once (ticked in Settings).
    /// Free = 1; any paid tier = the whole catalogue. NOTE: when the Tier enum
    /// collapses to free/manager/club/pro this becomes 1 / 1 / 3 / all — change
    /// it here only.
    var leagueAllowance: Int {
        tier.removesAds ? Leagues.all.count : 1
    }

    /// True when the user may enable more than one league (so the Settings
    /// checklist and in-game league chooser are worth showing as multi-select).
    var canHaveMultipleLeagues: Bool { leagueAllowance > 1 }

    /// Local testing override — flips the tier with no purchase. Pre-release only;
    /// gate behind a dev flag before shipping (production reads RevenueCat).
    func setDevTier(_ tier: Tier) {
        self.tier = tier
        self.verified = true
    }

    /// Applied by `PurchaseService` once it resolves the live entitlements.
    func apply(tier: Tier) {
        self.tier = tier
        self.verified = true
    }

    func refresh() async {
        await PurchaseService.shared.refreshTier()
    }
}
