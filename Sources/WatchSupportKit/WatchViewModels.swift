import Foundation
import DomainKit
import SnapshotKit
import WatchConnectivityKit

/// Glanceable fleet summary for the watch's first screen — a pure projection of a ``WatchSnapshot``.
public struct FleetSummaryViewModel: Equatable, Sendable {
    public let online: Int
    public let warning: Int
    public let critical: Int
    public let offline: Int
    public let total: Int
    public let hasData: Bool
    public let alertCount: Int
    public let lastUpdated: Date?

    public init(_ snapshot: WatchSnapshot) {
        self.online = snapshot.fleet.online
        self.warning = snapshot.fleet.warning
        self.critical = snapshot.fleet.critical
        self.offline = snapshot.fleet.offline
        self.total = snapshot.fleet.total
        self.hasData = snapshot.hasData
        self.alertCount = snapshot.alerts.count
        self.lastUpdated = snapshot.lastUpdated
    }

    /// One-line status, severity-first, for a large glanceable headline. Pluralized via the catalog
    /// ("2 warnings" / "2 advertencias" in the compiled app build).
    public var headline: String {
        guard hasData else { return loc("No data") }
        if critical > 0 { return loc("\(critical) critical") }
        if warning > 0 { return loc("\(warning) warning") }
        return loc("All clear")
    }

    /// "8/10 online" — the glance subtitle, localized ("8/10 en línea").
    public var onlineSummary: String { loc("\(online)/\(total) online") }

    /// True when there's something worth tapping into the Alerts screen for.
    public var hasAlerts: Bool { alertCount > 0 }
}

/// The Critical Alerts list — a pure projection that enforces the watch's severity hierarchy.
public struct AlertListViewModel: Equatable, Sendable {
    /// Alerts ordered for a watch: most severe first, then most recent. (`AlertSeverity` is `Comparable`.)
    public let alerts: [WidgetAlert]

    public init(_ snapshot: WatchSnapshot) {
        self.alerts = snapshot.alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.raisedAt > rhs.raisedAt
        }
    }

    public var isEmpty: Bool { alerts.isEmpty }
}

/// One alert as a watch row needs it. `message` is the localized text the iPhone already built and sent;
/// `severityLabel` is localized on the watch (and locale-injectable for tests).
public struct AlertRowViewModel: Equatable, Sendable {
    private let alert: WidgetAlert

    public init(_ alert: WidgetAlert) {
        self.alert = alert
    }

    public var deviceName: String { alert.deviceName }
    public var message: String { alert.message }
    public var severity: AlertSeverity { alert.severity }
    public var raisedAt: Date { alert.raisedAt }
    public var severityLabel: String { alert.severity.watchLabel }
}

/// The Devices list — every synced device, ordered worst-status-first for attention, then by name.
public struct DeviceListViewModel: Equatable, Sendable {
    public let devices: [WatchDeviceSnapshot]

    public init(_ snapshot: WatchSnapshot) {
        self.devices = snapshot.devices.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.attentionRank > rhs.status.attentionRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public var isEmpty: Bool { devices.isEmpty }
}

/// A single device's snapshot for the Device Snapshot screen — name, status, and the last-known
/// operational detail (battery, connectivity, last seen, a few telemetry highlights). Pure projection,
/// locale-injectable so its localized labels are testable.
public struct DeviceSnapshotViewModel: Equatable, Sendable {
    private let device: WatchDeviceSnapshot

    public init(_ device: WatchDeviceSnapshot) {
        self.device = device
    }

    public var name: String { device.name }
    public var assetName: String? { device.assetName }
    public var status: DeviceStatus { device.status }
    public var statusLabel: String { device.status.watchLabel }

    public var battery: BatteryStatus? { device.battery }
    public var hasBattery: Bool { device.battery != nil }
    /// e.g. "84%" — rounded percentage, or `nil` when battery is unknown.
    public var batteryText: String? {
        device.battery.map { "\(Int($0.percentage.rounded()))%" }
    }
    public var isCharging: Bool { device.battery?.isCharging ?? false }

    public var connectivityLabel: String { device.connectivity.state.watchLabel }
    public var lastSeenAt: Date? { device.connectivity.lastSeenAt }

    /// Localized metric name + formatted value, e.g. ("Temperature", "12.0 °C").
    public struct TelemetryRow: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let value: String
    }

    public var hasTelemetry: Bool { !device.telemetry.isEmpty }

    public var telemetry: [TelemetryRow] {
        device.telemetry.map { highlight in
            let name = AlertText.metricName(highlight.metric)
            return TelemetryRow(id: name, name: name, value: MeasurementText.string(highlight.value))
        }
    }
}

// MARK: - Localized labels (watch-local presentation; tests use these via the view models)

extension DeviceStatus {
    /// Worst-first ordering for the Devices list: critical, then warning, then offline, then nominal.
    var attentionRank: Int {
        switch self {
        case .critical: 3
        case .warning: 2
        case .offline: 1
        case .nominal: 0
        }
    }

    var watchLabel: String {
        switch self {
        case .nominal: loc("Online")
        case .warning: loc("Warning")
        case .critical: loc("Critical")
        case .offline: loc("Offline")
        }
    }
}

extension ConnectivityStatus.State {
    var watchLabel: String {
        switch self {
        case .online: loc("Online")
        case .degraded: loc("Degraded")
        case .offline: loc("Offline")
        }
    }
}

extension AlertSeverity {
    var watchLabel: String {
        switch self {
        case .info: loc("Info")
        case .warning: loc("Warning")
        case .critical: loc("Critical")
        }
    }
}
