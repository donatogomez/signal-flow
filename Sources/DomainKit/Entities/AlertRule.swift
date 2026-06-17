import Foundation

/// A rule that raises an ``Alert`` when a metric breaches a ``Threshold``.
///
/// ``evaluate(_:on:at:alertID:)`` is a pure function — given the same inputs it always produces the
/// same result — which makes alerting exhaustively testable without any infrastructure.
public struct AlertRule: Identifiable, Hashable, Sendable, Codable {
    public let id: AlertRuleID
    public let name: String
    public let metric: MetricKind
    public let threshold: Threshold
    public let severity: AlertSeverity
    public let isEnabled: Bool

    public init(
        id: AlertRuleID = AlertRuleID(),
        name: String,
        metric: MetricKind,
        threshold: Threshold,
        severity: AlertSeverity,
        isEnabled: Bool = true
    ) throws {
        self.id = id
        self.name = try DomainText.validatedName(name, context: "AlertRule")
        self.metric = metric
        self.threshold = threshold
        self.severity = severity
        self.isEnabled = isEnabled
    }

    /// Returns an ``Alert`` if `value` breaches this rule, otherwise `nil`.
    ///
    /// The caller is responsible for pairing the value with a reading of this rule's `metric`. The
    /// `alertID` is injected so callers (and tests) control identity deterministically.
    public func evaluate(
        _ value: MeasuredValue,
        on deviceID: DeviceID,
        at date: Date,
        alertID: AlertID = AlertID()
    ) -> Alert? {
        guard isEnabled, threshold.isBreached(by: value.magnitude) else { return nil }
        return Alert(
            id: alertID,
            deviceID: deviceID,
            ruleID: id,
            metric: metric,
            severity: severity,
            message: "\(metric.displayName) \(value) is outside the acceptable range (\(threshold))",
            observedValue: value,
            raisedAt: date
        )
    }
}
