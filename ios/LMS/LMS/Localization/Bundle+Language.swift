import Foundation

/// In-app language override. By default `Bundle.main` resolves localized strings
/// against the device language; to let the user pick a language *inside* the app
/// we re-point `Bundle.main` at a specific `.lproj` so `String(localized:)`,
/// `NSLocalizedString`, and SwiftUI's `Text(LocalizedStringKey)` all resolve in
/// the chosen language immediately — no relaunch.
///
/// Done by swapping `Bundle.main`'s class to a subclass that overrides string
/// lookup. This is the standard, App Store–safe technique (no private API).
private var languageBundleKey: UInt8 = 0

private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &languageBundleKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// The bundle `AppString` resolves against: the selected language's `.lproj`
    /// sub-bundle, or `Bundle.main` for the device default. `String(localized:)`
    /// bypasses the swizzle (it resolves via CFBundle, not the ObjC
    /// `localizedString` override), so passing this bundle explicitly is what
    /// makes plain strings follow the in-app language. Written only on the main
    /// thread (language changes); read anywhere.
    nonisolated(unsafe) private(set) static var appLanguageBundle: Bundle = .main

    /// The locale matching the selected language, for date/number formatting and
    /// for `\.locale` when rendering off the main view tree (e.g. the share-card
    /// `ImageRenderer`, which doesn't inherit the app root's locale).
    nonisolated(unsafe) private(set) static var appLocale: Locale = .autoupdatingCurrent

    /// Point `Bundle.main` at the `.lproj` for `code` (e.g. "es"), or pass `nil`
    /// to fall back to the device language. Safe to call repeatedly.
    static func setAppLanguage(_ code: String?) {
        // Swap the class once so SwiftUI `Text`/`NSLocalizedString` route through
        // the override.
        if !(Bundle.main is LanguageOverrideBundle) {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }
        let path = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        appLanguageBundle = path.flatMap(Bundle.init(path:)) ?? .main
        appLocale = code.map { Locale(identifier: $0) } ?? .autoupdatingCurrent
    }
}

/// Localizes `key` honoring the in-app language override. Use this instead of
/// `String(localized:)` for any non-`Text` string (enum labels, share-card copy,
/// alerts): plain `String(localized:)` ignores the override and always uses the
/// device language. SwiftUI `Text("…")` is fine as-is (it respects the swizzle).
func AppString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Bundle.appLanguageBundle)
}
