import Foundation

/// A raised alert: the record that a device's value breached an ``AlertRule``.
///
/// Acknowledgement is a forward-only lifecycle — an already-acknowledged alert cannot be
/// acknowledged again — enforced by ``acknowledge(at:)``.
public struct Alert: Identifiable, Hashable, Sendable, Codable {
    public let id: AlertID
    public let deviceID: DeviceID
    public let ruleID: AlertRuleID
    public let metric: MetricKind
    public let severity: AlertSeverity
    public let message: String
    public let observedValue: MeasuredValue
    public let raisedAt: Date
    public private(set) var acknowledgedAt: Date?

    public init(
        id: AlertID = AlertID(),
        deviceID: DeviceID,
        ruleID: AlertRuleID,
        metric: MetricKind,
        severity: AlertSeverity,
        message: String,
        observedValue: MeasuredValue,
        raisedAt: Date,
        acknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.ruleID = ruleID
        self.metric = metric
        self.severity = severity
        self.message = message
        self.observedValue = observedValue
        self.raisedAt = raisedAt
        self.acknowledgedAt = acknowledgedAt
    }

    public var isAcknowledged: Bool { acknowledgedAt != nil }

    /// Acknowledges the alert. Throws if it was already acknowledged.
    public mutating func acknowledge(at date: Date) throws {
        guard acknowledgedAt == nil else { throw DomainError.alertAlreadyAcknowledged(id) }
        acknowledgedAt = date
    }
}
