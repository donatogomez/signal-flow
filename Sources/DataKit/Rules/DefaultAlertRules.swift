import DomainKit

/// Deterministic default alert rules per asset kind.
///
/// The *thresholds* (which values warrant an alert) are configuration and therefore a data-layer
/// concern — but the rule **type** and its breach logic are `DomainKit`'s. DataKit picks the
/// thresholds; `AlertRule.evaluate` decides breaches. No domain rule is reimplemented here.
public enum DefaultAlertRules {

    public static func rules(for kind: AssetKind) throws -> [AlertRule] {
        switch kind {
        case .refrigeratedTruck, .coldChainContainer:
            return [
                try rule("Temperature above safe limit", .temperature, upper: 8, severity: .critical),
                try rule("Battery low", .batteryLevel, lower: 15, severity: .warning),
                try rule("Weak signal", .signalStrength, lower: -100, severity: .warning),
            ]
        case .greenhouse:
            return [
                try rule("Temperature out of range", .temperature, lower: 15, upper: 32, severity: .warning),
                try rule("CO₂ too high", .carbonDioxide, upper: 1200, severity: .warning),
                try rule("Humidity out of range", .humidity, lower: 40, upper: 80, severity: .info),
            ]
        case .warehouse:
            return [
                try rule("Temperature out of range", .temperature, lower: 12, upper: 28, severity: .warning),
                try rule("Battery low", .batteryLevel, lower: 15, severity: .warning),
            ]
        case .industrialEquipment, .environmentalStation:
            return [
                try rule("Temperature out of range", .temperature, lower: -10, upper: 45, severity: .warning),
                try rule("Humidity out of range", .humidity, lower: 15, upper: 95, severity: .info),
            ]
        }
    }

    private static func rule(
        _ name: String,
        _ metric: MetricKind,
        lower: Double? = nil,
        upper: Double? = nil,
        severity: AlertSeverity
    ) throws -> AlertRule {
        try AlertRule(
            name: name,
            metric: metric,
            threshold: try Threshold(lowerBound: lower, upperBound: upper),
            severity: severity
        )
    }
}
