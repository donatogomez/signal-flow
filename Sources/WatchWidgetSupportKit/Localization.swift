import Foundation

/// Resolves a key against the watch widget extension's string catalog (`Bundle.module`). Localization
/// stays in the presentation layer; the complication reuses domain semantics from SnapshotKit's value
/// types and never localizes inside DomainKit.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

#if DEBUG
/// Test seam: the module bundle that carries the string catalog. SwiftPM copies `Localizable.xcstrings`
/// in raw (uncompiled), so tests assert the shipped translations by reading the catalog directly rather
/// than through `String(localized:)` — which, on the macOS test host, only ever resolves the English
/// source. The compiled localizations are exercised in the real watchOS extension build.
let watchWidgetSupportResourceBundle = Bundle.module
#endif
