import Foundation

/// Resolves a key against this feature's string catalog (`Bundle.module`). User-facing copy lives in
/// `Resources/Localizable.xcstrings`; domain semantics (status/severity/etc.) come pre-localized from
/// DesignSystemKit. Localization stays in the presentation layer — never in DomainKit.
func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
