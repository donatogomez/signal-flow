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
    public let message: String
    public let raisedAt: Date
    public let acknowledgedAt: Date?

    public var isAcknowledged: Bool { acknowledgedAt != nil }
}

/// The two lists the screen offers.
public enum AlertTab: String, CaseIterable, Sendable, Identifiable {
    case active, history
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .active: "Active"
        case .history: "History"
        }
    }
}

/// Severity filter offered in the toolbar.
public enum AlertSeverityFilter: String, CaseIterable, Sendable, Identifiable {
    case all, info, warning, critical
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "All severities"
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
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
