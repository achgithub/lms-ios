import SwiftUI

/// The five-tab navigation: Games, Players, Scores, Standings, Settings.
/// (Picks are entered inside a game — Games → Enter Picks — so the second tab
/// is the reusable player roster rather than a read-only picks view.)
struct RootTabView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var entitlements = Entitlements.shared
    @Environment(EnabledLeagues.self) private var enabled
    @Environment(\.scenePhase) private var scenePhase

    /// True when more leagues are enabled than the (possibly downgraded)
    /// subscription allows — the app is blocked until the user reduces them.
    private var mustReduceLeagues: Bool { !enabled.isWithinAllowance(entitlements) }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GamesListView()
                    .tabItem { Label("Games", systemImage: "trophy") }
                PlayersView()
                    .tabItem { Label("Players", systemImage: "person.2") }
                ScoresView()
                    .tabItem { Label("Scores", systemImage: "sportscourt") }
                StandingsView()
                    .tabItem { Label("Standings", systemImage: "list.number") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            // App-wide banner at the very bottom; only for ad-supported tiers.
            // Kept OUTSIDE the TabView (not a safeAreaInset on it) so it renders
            // reliably and never overlaps the tab bar's touch area.
            if entitlements.shouldShowAds {
                AdBannerView()
            }
        }
        .environment(entitlements)
        .sheet(isPresented: .constant(managerName.isEmpty)) {
            ManagerOnboardingView(managerName: $managerName)
        }
        // Subscription downgrade: block the whole app until the user trims their
        // enabled leagues back within the new allowance.
        .fullScreenCover(isPresented: .constant(mustReduceLeagues)) {
            LeagueDowngradeView()
                .environment(entitlements)
        }
        .task {
            PurchaseService.shared.configure()
            AdsBootstrap.start()
            InterstitialAdManager.shared.preload()
            RewardedAdManager.shared.preload()
            await entitlements.refresh()
            // Drop any leagues that no longer exist. Going over the subscription
            // allowance is handled by the blocking downgrade gate, not silently.
            EnabledLeagues.shared.pruneInvalid()
        }
        .onChange(of: scenePhase) { _, phase in
            // Timed interstitial on returning to the foreground.
            if phase == .active { InterstitialAdManager.shared.showIfDue() }
        }
    }
}
