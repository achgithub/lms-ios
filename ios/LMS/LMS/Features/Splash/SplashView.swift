import SwiftUI

/// Animated brand splash shown once at launch, over the instant (blank) system
/// launch screen. Uses the designer's PNG assets when present in the asset
/// catalog (`background`, `shield`, `sports_manager_wordmark`) and falls back to
/// SwiftUI-drawn placeholders built from the app's diagonal motif so it runs
/// before the artwork lands.
///
/// Animation timeline is FROZEN (do not change without sign-off):
///   0.0  background visible
///   0.3  shield fade in
///   0.8  "Sports Manager" fade in
///   1.2  league/product name fade in
///   1.5  shield pulse
///   2.5  transition to app
struct SplashView: View {
    /// Called at t=2.5s when the splash should hand off to the app.
    var onFinished: () -> Void = {}

    private static let fade = 0.5   // per-element fade duration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shieldOpacity = 0.0
    @State private var shieldScale = 1.0
    @State private var brandOpacity = 0.0
    @State private var nameOpacity = 0.0

    /// The product/league name shown under the wordmark (e.g. "Last Man Standing").
    private var productName: String { LeagueConfig.shared.appName }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                shield
                    .frame(width: 132, height: 156)
                    .opacity(shieldOpacity)
                    .scaleEffect(shieldScale)

                VStack(spacing: 8) {
                    wordmark
                        .opacity(brandOpacity)
                    Text(productName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Brand.onDark)
                        .opacity(nameOpacity)
                }
            }
        }
        .task { await run() }
    }

    // MARK: Timeline

    private func run() async {
        // Absolute cue times (s); we sleep the gaps between them so the schedule
        // is robust regardless of when the view actually appears.
        guard !reduceMotion else {
            shieldOpacity = 1; brandOpacity = 1; nameOpacity = 1
            await sleep(2.5)
            onFinished()
            return
        }

        await sleep(0.3)   // → shield fade in
        withAnimation(.easeIn(duration: Self.fade)) { shieldOpacity = 1 }
        await sleep(0.5)   // → 0.8 "Sports Manager" fade in
        withAnimation(.easeIn(duration: Self.fade)) { brandOpacity = 1 }
        await sleep(0.4)   // → 1.2 product name fade in
        withAnimation(.easeIn(duration: Self.fade)) { nameOpacity = 1 }
        await sleep(0.3)   // → 1.5 shield pulse
        withAnimation(.easeInOut(duration: 0.18)) { shieldScale = 1.12 }
        await sleep(0.18)
        withAnimation(.easeInOut(duration: 0.18)) { shieldScale = 1.0 }
        await sleep(0.82)  // → 2.5 handoff to app
        onFinished()
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Elements (asset-or-drawn)

    @ViewBuilder private var background: some View {
        if let img = Brand.image("background") {
            img.resizable().scaledToFill()
        } else {
            LinearGradient(
                colors: [Brand.backgroundTop, Brand.backgroundBottom],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    @ViewBuilder private var shield: some View {
        if let img = Brand.image("shield") {
            img.resizable().scaledToFit()
        } else {
            ShieldEmblem()
        }
    }

    @ViewBuilder private var wordmark: some View {
        if let img = Brand.image("sports_manager_wordmark") {
            img.resizable().scaledToFit().frame(height: 30)
        } else {
            Text("Sports Manager")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.onDark)
        }
    }
}

// MARK: - Brand tokens

/// Splash brand tokens. Colors are placeholders pending the approved palette —
/// per-product variants change only the accent (`accent`). Swap these (or drop
/// in the PNG assets) without touching the animation code.
enum Brand {
    static let accent = Color(hex: "1FA971")        // product accent (change per variant)
    static let backgroundTop = Color(hex: "0C2A20")
    static let backgroundBottom = Color(hex: "061712")
    static let onDark = Color.white

    /// An asset-catalog image by name, or nil if the slot is still empty (so the
    /// drawn fallback is used until the designer's PNG is added).
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        return UIImage(named: name) != nil ? Image(name) : nil
        #else
        return nil
        #endif
    }
}

// MARK: - Drawn fallback emblem (diagonal-split shield)

/// A simple shield using the app's two-colour diagonal split (§15 motif) with a
/// soccerball mark — the placeholder until `shield.png` is supplied.
private struct ShieldEmblem: View {
    var body: some View {
        ZStack {
            ShieldShape()
                .fill(Brand.accent)
            ShieldShape()
                .fill(Brand.accent.opacity(0.0))
                .overlay {
                    DiagonalSplitShape(invert: true)
                        .fill(.black.opacity(0.18))
                        .clipShape(ShieldShape())
                }
            Image(systemName: "soccerball")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white)
            ShieldShape()
                .stroke(.white.opacity(0.9), lineWidth: 3)
        }
    }
}

/// A heraldic shield: square shoulders, curved sides tapering to a point.
private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.55))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.minY + h * 0.9)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + h * 0.55),
            control: CGPoint(x: rect.minX, y: rect.minY + h * 0.9)
        )
        p.closeSubpath()
        return p
    }
}

#Preview {
    SplashView()
}
