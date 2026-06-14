import Foundation

/// Gates a user *action* behind a rewarded ad for ad-supported (free) users.
///
/// - Subscribers (ads removed) run the action immediately.
/// - Free users see a rewarded ad first; the action runs only if the reward is
///   earned (i.e. they watched it). Dismissing early skips the action.
/// - If no ad is available to show (no fill, or the Google Mobile Ads SDK isn't
///   linked yet), the action runs anyway — we never hard-block a real task on ad
///   availability.
///
/// This is the single client-side free/subscriber gate now that the Worker
/// serves one shared score cache (freshness is no longer a tier). Use it for
/// explicit refresh actions and exports — NOT for passively opening a screen.
@MainActor
enum AdGate {
    /// Runs `action`, showing a rewarded ad first for free users.
    static func run(_ action: @escaping () -> Void) {
        guard Entitlements.shared.shouldShowAds else { action(); return }  // subscriber: no ad
        guard RewardedAdManager.shared.isReady else { action(); return }   // no ad to show: don't block
        RewardedAdManager.shared.show { earned in
            if earned { action() }
        }
    }
}
