import SwiftUI

/// The five tabs. Tagged so the selection survives the language re-key (see
/// `AppRootView`): changing language recreates this view, so the selection lives
/// in the parent and is restored via the binding rather than resetting to Games.
enum RootTab: Hashable { case games, players, scores, standings, settings }

/// The five-tab navigation: Games, Players, Scores, Standings, Settings.
/// (Picks are entered inside a game — Games → Enter Picks — so the second tab
/// is the reusable player roster rather than a read-only picks view.)
struct RootTabView: View {
    /// True while the launch splash is still showing — modal presentations
    /// (onboarding, downgrade gate) wait until it's gone so they don't pop over
    /// the splash (a `.sheet`/`.fullScreenCover` presents at the window level).
    var splashActive: Bool = false
    /// Owned by `AppRootView` so it persists across the language re-key.
    @Binding var selection: RootTab
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @State private var entitlements = Entitlements.shared
    @Environment(EnabledLeagues.self) private var enabled
    // @Environment(\.scenePhase) private var scenePhase  // interstitial dropped 2026-06-15

    /// True when more leagues are enabled than the (possibly downgraded)
    /// subscription allows — the app is blocked until the user reduces them.
    private var mustReduceLeagues: Bool { !enabled.isWithinAllowance(entitlements) }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                GamesListView()
                    .tabItem { Label("Games", systemImage: "trophy") }
                    .tag(RootTab.games)
                PlayersView()
                    .tabItem { Label("Players", systemImage: "person.2") }
                    .tag(RootTab.players)
                ScoresView()
                    .tabItem { Label("Scores", systemImage: "sportscourt") }
                    .tag(RootTab.scores)
                StandingsView()
                    .tabItem { Label("Standings", systemImage: "list.number") }
                    .tag(RootTab.standings)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(RootTab.settings)
            }
            // App-wide banner at the very bottom; only for ad-supported tiers.
            // Kept OUTSIDE the TabView (not a safeAreaInset on it) so it renders
            // reliably and never overlaps the tab bar's touch area.
            if entitlements.shouldShowAds {
                AdBannerView()
            }
        }
        .environment(entitlements)
        .sheet(isPresented: .constant(!splashActive && managerName.isEmpty)) {
            ManagerOnboardingView(managerName: $managerName)
        }
        // Subscription downgrade: block the whole app until the user trims their
        // enabled leagues back within the new allowance.
        .fullScreenCover(isPresented: .constant(!splashActive && mustReduceLeagues)) {
            LeagueDowngradeView()
                .environment(entitlements)
        }
        .task {
            PurchaseService.shared.configure()
            // Skip ad bootstrap under UI tests so the ATT / UMP consent dialogs
            // never appear and make the launch flow flaky.
            if !ProcessInfo.processInfo.arguments.contains("-uitests") {
                AdsBootstrap.start()
                // Interstitial dropped (low value for this workflow app, 2026-06-15).
                // Code kept in InterstitialAdManager; re-enable by uncommenting here
                // and the scenePhase trigger below.
                // InterstitialAdManager.shared.preload()
                RewardedAdManager.shared.preload()
            }
            await entitlements.refresh()
            // Drop any leagues that no longer exist. Going over the subscription
            // allowance is handled by the blocking downgrade gate, not silently.
            EnabledLeagues.shared.pruneInvalid()
        }
        // Interstitial dropped (2026-06-15) — foreground trigger disabled.
        // .onChange(of: scenePhase) { _, phase in
        //     if phase == .active { InterstitialAdManager.shared.showIfDue() }
        // }
    }
}
