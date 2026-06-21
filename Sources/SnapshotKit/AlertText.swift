import Foundation
import DomainKit

/// Builds the **localized** human-readable alert message for glance surfaces (widgets, Live Activity,
/// watch) from a domain `Alert`'s structured fields.
///
/// The domain (`AlertRule.evaluate`) stores a language-neutral English diagnostic in `Alert.message`;
/// it is **not** shown to users. Every surface instead renders this localized message, derived from the
/// metric + observed value, so the text follows the device language. SnapshotKit owns this for the
/// glance surfaces because they can't reach DesignSystemKit; the app features use the equivalent helper
/// in DesignSystemKit. (The small overlap in the two catalogs is the price of the boundary.)
public enum AlertText {
    public static func message(metric: MetricKind, value: MeasuredValue) -> String {
        let valueText = "\(value)"
        return String(localized: "\(metricName(metric)) \(valueText) is outside the acceptable range", bundle: .module)
    }

    static func metricName(_ metric: MetricKind) -> String {
        switch metric {
        case .temperature: String(localized: "Temperature", bundle: .module)
        case .humidity: String(localized: "Humidity", bundle: .module)
        case .carbonDioxide: String(localized: "Carbon dioxide", bundle: .module)
        case .batteryLevel: String(localized: "Battery level", bundle: .module)
        case .signalStrength: String(localized: "Signal strength", bundle: .module)
        case .custom("pressure"): String(localized: "Pressure", bundle: .module)
        case .custom(let key): key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
