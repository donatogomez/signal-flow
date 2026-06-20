import Foundation

/// Resolves a key against the app shell's string catalog (`Bundle.module`) — the tab bar labels.
/// Localization stays in the presentation layer; the composition root owns no domain copy.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
