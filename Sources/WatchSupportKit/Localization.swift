import Foundation

/// Resolves a key against the watch app's string catalog (`Bundle.module`). Localization stays in the
/// presentation layer; the watch reuses domain semantics from SnapshotKit's value types.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
