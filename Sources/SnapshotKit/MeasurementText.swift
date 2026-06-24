import Foundation
import DomainKit

/// Operator-friendly rendering of a domain ``MeasuredValue`` for the glance surfaces (widgets, watch,
/// Live Activity, App Intents). **Presentation only** — it never mutates the underlying value.
///
/// The domain keeps full `Double` precision; operators must not see it. The rule is the same everywhere:
/// at most one decimal place, a whole number when the fraction is zero, locale-aware separators, with the
/// unit symbol. So `8.15940676719765 °C` reads `8.2 °C` and `14.968526080417478 %` reads `15 %`.
///
/// DesignSystemKit carries an equivalent helper for the in-app UI (it can't depend on SnapshotKit); the
/// small duplication is the price of the module boundary, exactly like the `AlertText` catalogs.
public enum MeasurementText {
    public static func string(_ value: MeasuredValue, locale: Locale = .current) -> String {
        let number = value.magnitude.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return value.unit.symbol.isEmpty ? number : "\(number) \(value.unit.symbol)"
    }
}
