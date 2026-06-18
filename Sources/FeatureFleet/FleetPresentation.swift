import DomainKit

/// A single row in the fleet list — a flat, render-ready projection of a device within its asset.
/// Presentation models are immutable value types derived from domain entities; the view never sees a
/// `Device` or `Asset` directly.
public struct FleetRow: Identifiable, Sendable, Hashable {
    public let id: DeviceID
    public let deviceName: String
    public let assetName: String
    public let assetKind: AssetKind
    public let status: DeviceStatus
    public let connectivity: ConnectivityStatus.State
    public let battery: BatteryStatus?
    public let activeAlertCount: Int
}

/// Sort orders offered in the fleet toolbar.
public enum FleetSort: String, CaseIterable, Sendable, Identifiable {
    case status, name, battery, alerts
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .status: "Status"
        case .name: "Name"
        case .battery: "Battery"
        case .alerts: "Alerts"
        }
    }

    /// Severity-first ordering so the most urgent devices surface at the top.
    func areInOrder(_ a: FleetRow, _ b: FleetRow) -> Bool {
        switch self {
        case .name:
            a.deviceName.localizedCaseInsensitiveCompare(b.deviceName) == .orderedAscending
        case .status:
            rank(a.status) != rank(b.status)
                ? rank(a.status) > rank(b.status)
                : a.deviceName.localizedCaseInsensitiveCompare(b.deviceName) == .orderedAscending
        case .battery:
            (a.battery?.percentage ?? .infinity) < (b.battery?.percentage ?? .infinity)
        case .alerts:
            a.activeAlertCount != b.activeAlertCount
                ? a.activeAlertCount > b.activeAlertCount
                : a.deviceName.localizedCaseInsensitiveCompare(b.deviceName) == .orderedAscending
        }
    }

    private func rank(_ status: DeviceStatus) -> Int {
        switch status {
        case .critical: 3
        case .warning: 2
        case .nominal: 1
        case .offline: 0
        }
    }
}

/// Status filter offered in the fleet toolbar.
public enum FleetStatusFilter: String, CaseIterable, Sendable, Identifiable {
    case all, nominal, warning, critical, offline
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .nominal: "Nominal"
        case .warning: "Warning"
        case .critical: "Critical"
        case .offline: "Offline"
        }
    }

    func matches(_ status: DeviceStatus) -> Bool {
        switch self {
        case .all: true
        case .nominal: status == .nominal
        case .warning: status == .warning
        case .critical: status == .critical
        case .offline: status == .offline
        }
    }
}
