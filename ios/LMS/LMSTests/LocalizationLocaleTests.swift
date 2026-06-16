import Testing
import Foundation
@testable import LMS

/// Pins down which `String(localized:)` lever selects the in-app language table
/// from the app bundle (where the compiled .lproj live).
struct LocalizationLocaleTests {
    private func esBundle() throws -> Bundle {
        let appBundle = Bundle(for: Entitlements.self)
        let esPath = try #require(appBundle.path(forResource: "es", ofType: "lproj"))
        return try #require(Bundle(path: esPath))
    }

    @Test func subBundleStringLocalized() throws {
        // Does String(localized:bundle:) honor a language sub-bundle? (handles interpolation)
        #expect(String(localized: "Anonymous", bundle: try esBundle()) == "Anónimo")
        #expect(String(localized: "Round \(3)", bundle: try esBundle()) == "Ronda 3")
    }

    @Test func subBundleLegacyLookup() throws {
        #expect(try esBundle().localizedString(forKey: "Anonymous", value: nil, table: nil) == "Anónimo")
    }

    // MARK: - Format-specifier parity

    /// Every translation must use the same ordered set of format specifiers as its
    /// English source key, accounting for positional specifiers (%1$@, %2$lld). A
    /// mismatch means an argument gets fed to the wrong specifier at runtime — e.g.
    /// an Int into %@ or a String into %lld — which is garbage output or a crash.
    /// This guards the exact bug found in DE/IT during review.
    @Test func formatSpecifierParityAcrossLanguages() throws {
        let appBundle = Bundle(for: Entitlements.self)
        for lang in ["es", "de", "fr", "nl", "it"] {
            let path = try #require(
                appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang),
                "missing \(lang) Localizable.strings"
            )
            let dict = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            for (sourceKey, translation) in dict {
                #expect(
                    Self.specifierTypes(sourceKey) == Self.specifierTypes(translation),
                    "[\(lang)] specifier mismatch — key: \(sourceKey) → value: \(translation)"
                )
            }
        }
    }

    /// Proves the parity helper actually distinguishes the bug class: a
    /// non-positional swap is a mismatch, while a positional reorder is allowed.
    @Test func specifierHelperDetectsSwaps() {
        #expect(Self.specifierTypes("%lld %@") != Self.specifierTypes("%@ %lld"))      // the DE/IT bug
        #expect(Self.specifierTypes("%lld %@") == Self.specifierTypes("%2$@ %1$lld"))  // the fix
    }

    /// The ordered specifier *types* ("@" = object, "#" = integer) in a format
    /// string. Positional specifiers are reordered by their index so a translation
    /// may legitimately move them (e.g. "%2$@ … %1$lld") and still match.
    private static func specifierTypes(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(@|lld|ld|d|lf|f|i|u)")
        let ns = s as NSString
        var items: [(pos: Int?, type: String)] = []
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let type = ns.substring(with: m.range(at: 2)) == "@" ? "@" : "#"
            let posR = m.range(at: 1)
            let pos = posR.location == NSNotFound ? nil : Int(ns.substring(with: posR))
            items.append((pos, type))
        }
        if items.contains(where: { $0.pos != nil }) {
            items.sort { ($0.pos ?? .max) < ($1.pos ?? .max) }
        }
        return items.map(\.type)
    }
}
