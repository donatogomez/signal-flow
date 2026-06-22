import Foundation

/// Resolves a key against the watch app's string catalog (`Bundle.module`). Localization stays in the
/// presentation layer; the watch reuses domain semantics from SnapshotKit's value types.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

#if DEBUG
/// Test seam: the module bundle that carries the string catalog. SwiftPM copies `Localizable.xcstrings`
/// in raw (uncompiled), so tests assert the shipped translations by reading the catalog directly rather
/// than through `String(localized:)` — which, on the macOS test host, only ever resolves the English
/// source. The compiled localizations are exercised in the real watchOS app build.
let watchSupportResourceBundle = Bundle.module
#endif
