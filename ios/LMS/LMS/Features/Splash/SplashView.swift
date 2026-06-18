import SwiftUI

/// Brand splash shown once at launch, over the instant (blank) system launch
/// screen. v2: the shared cross-app brand moment — background, then the
/// master shield, then the "SPORTS MANAGER" wordmark, then this app's own
/// name in its accent colour. Every Sports Manager app shows the same
/// shield/background/wordmark beats; only the final app-name line and its
/// colour vary per app. See docs/brand/style-guide.md.
///
/// Timeline: background fades in immediately; shield scales+fades in
/// (~0.5s); wordmark fades in (~0.35s); app name fades in in the app's
/// accent colour (~0.35s); hold ~1s; hand off.
struct SplashView: View {
    /// Called when the splash should hand off to the app.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backgroundOpacity = 0.0
    @State private var shieldOpacity = 0.0
    @State private var shieldScale = 0.85
    @State private var wordmarkOpacity = 0.0
    @State private var appNameOpacity = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let background = Brand.image("background") {
                background
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
            }

            VStack(spacing: 18) {
                if let shield = Brand.image("shield") {
                    shield
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .opacity(shieldOpacity)
                        .scaleEffect(shieldScale)
                }

                VStack(spacing: 4) {
                    Text("SPORTS MANAGER")
                        .font(.custom("MontserratThin-Black", size: 15))
                        .kerning(2)
                        .foregroundStyle(Brand.masterBlue)
                        .opacity(wordmarkOpacity)

                    Text("LAST MAN STANDING")
                        .font(.custom("MontserratThin-ExtraBold", size: 22))
                        .kerning(1)
                        .foregroundStyle(Brand.accent)
                        .opacity(appNameOpacity)
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        guard !reduceMotion else {
            backgroundOpacity = 1
            shieldOpacity = 1
            shieldScale = 1
            wordmarkOpacity = 1
            appNameOpacity = 1
            try? await Task.sleep(for: .seconds(1.5))
            onFinished()
            return
        }

        withAnimation(.easeIn(duration: 0.3)) { backgroundOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.2))
        withAnimation(.easeOut(duration: 0.5)) {
            shieldOpacity = 1
            shieldScale = 1
        }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.easeIn(duration: 0.35)) { wordmarkOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.25))
        withAnimation(.easeIn(duration: 0.35)) { appNameOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.35 + 1.0))
        onFinished()
    }
}

/// Brand tokens shared across the Sports Manager app family.
/// See docs/brand/style-guide.md for the full palette.
enum Brand {
    /// This app's own accent colour (LMS = orange). Swap per product variant.
    static let accent = Color(hex: "F97316")

    /// The shared master brand colour used for the splash shield/wordmark
    /// across every app in the family — NOT per-app.
    static let masterBlue = Color(hex: "3DA8FF")

    /// An asset-catalog image by name, or nil if the slot is empty (so a caller
    /// can fall back). Guards against an empty/zero-size imageset.
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(named: name), ui.size.width > 0 { return Image(uiImage: ui) }
        return nil
        #else
        return nil
        #endif
    }
}

#Preview {
    SplashView()
}
