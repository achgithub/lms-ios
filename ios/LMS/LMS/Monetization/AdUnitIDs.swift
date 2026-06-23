import Foundation

/// AdMob unit IDs. The App ID also goes in Info.plist as `GADApplicationIdentifier`
/// (real always — only the ad UNIT ids switch for test ads, never the App ID).
///
/// `useTestAds = true` while the app is TestFlight-only: AdMob can't review an
/// app with no App Store URL yet, so the real ad units serve no fill at all
/// pre-review. Google's own guidance for this exact situation is to use their
/// demo ad unit IDs (`Demo` below) rather than real ones, partly to avoid any
/// risk of invalid-traffic flags on real inventory during testing. **Flip this
/// to `false` once submitting to the App Store** (Phase 5 of the route-to-live
/// plan) — that's the one deliberate edit this file needs before release.
enum AdUnitIDs {
    static let useTestAds = true

    static let appID = "ca-app-pub-3510617456822042~1632957503"

    /// Real production ad unit IDs — untouched, kept for when `useTestAds` flips.
    private enum Live {
        static let banner = "ca-app-pub-3510617456822042/4127258904"
        static let interstitial = "ca-app-pub-3510617456822042/6174837744"
        static let rewarded = "ca-app-pub-3510617456822042/7400289502"
    }

    /// Google's official demo ad unit IDs — always serve a test creative,
    /// regardless of app review/account status. See developers.google.com/admob/ios/test-ads.
    private enum Demo {
        static let banner = "ca-app-pub-3940256099942544/2435281174"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        static let rewarded = "ca-app-pub-3940256099942544/1712485313"
    }

    static var banner: String { useTestAds ? Demo.banner : Live.banner }
    static var interstitial: String { useTestAds ? Demo.interstitial : Live.interstitial }
    static var rewarded: String { useTestAds ? Demo.rewarded : Live.rewarded }
}
