import Foundation
import DomainKit

/// A render-ready alert row: the domain `Alert` plus its resolved device/asset context.
public struct AlertRow: Identifiable, Sendable, Hashable {
    public let id: AlertID
    public let deviceID: DeviceID
    public let deviceName: String
    public let assetName: String
    public let assetKind: AssetKind
    public let severity: AlertSeverity
    /// The metric in trouble + its observed value, already formatted by the presentation layer — so the
    /// inbox can surface the value cleanly without re-parsing the localized message.
    public let metric: MetricKind
    public let valueText: String
    public let message: String
    public let raisedAt: Date
    public let acknowledgedAt: Date?

    public var isAcknowledged: Bool { acknowledgedAt != nil }
}

/// The three inbox states the screen offers. `active`/`acknowledged` are both still-firing alerts, split
/// by whether the operator has acknowledged them; `resolved` is the cleared history.
public enum AlertTab: String, CaseIterable, Sendable, Identifiable {
    case active, acknowledged, resolved
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .active: loc("Active")
        case .acknowledged: loc("Acknowledged")
        case .resolved: loc("Resolved")
        }
    }
}

/// Severity filter offered in the toolbar.
public enum AlertSeverityFilter: String, CaseIterable, Sendable, Identifiable {
    case all, info, warning, critical
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: loc("All severities")
        case .info: loc("Info")
        case .warning: loc("Warning")
        case .critical: loc("Critical")
        }
    }

    func matches(_ severity: AlertSeverity) -> Bool {
        switch self {
        case .all: true
        case .info: severity == .info
        case .warning: severity == .warning
        case .critical: severity == .critical
        }
    }
}
