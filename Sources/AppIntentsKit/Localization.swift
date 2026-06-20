import Foundation

/// Localized `String` against this module's catalog (`Bundle.module`) — for runtime copy like the
/// spoken fleet summary.
///
/// App Intents *metadata* (intent titles/descriptions, shortcut short-titles) instead uses an inline
/// `LocalizedStringResource("…", bundle: .atURL(Bundle.module.bundleURL))`: the metadata extractor parses
/// those statically and rejects a wrapper-function initializer, so they can't go through this helper.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
