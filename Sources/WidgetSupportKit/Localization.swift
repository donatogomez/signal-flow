import Foundation

/// Resolves a key against the widgets' string catalog (`Bundle.module`). Localization stays in the
/// presentation layer; domain semantics arrive already-localized from DesignSystemKit.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
