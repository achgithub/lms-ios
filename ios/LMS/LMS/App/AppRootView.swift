import SwiftUI

/// App entry view: shows the animated brand splash once over the main UI, then
/// hands off at the frozen 2.5s mark. The tab view loads underneath during the
/// splash so its startup work (ads, purchases) is already running on handoff.
struct AppRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootTabView()
                .environment(EnabledLeagues.shared)

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
