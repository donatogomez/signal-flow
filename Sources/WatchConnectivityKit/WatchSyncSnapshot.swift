import Foundation
import DomainKit
import SnapshotKit

/// One compact telemetry highlight the watch can show on a device snapshot: the metric, its latest
/// value, and an optional short recent **history** (oldest→newest magnitudes) for a sparkline + trend
/// delta. Pure `Codable` so it crosses the WatchConnectivity boundary cheaply; the watch localizes the
/// metric name (via `SnapshotKit.AlertText`) and formats the value at render time.
public struct WatchTelemetryHighlight: Codable, Sendable, Equatable, Hashable {
    public let metric: MetricKind
    public let value: MeasuredValue
    /// Recent magnitudes for this metric, oldest→newest, for the watch's mini trend. Empty when no
    /// history is available; a sparkline is shown only when there are at least two points.
    public let history: [Double]
    /// Minutes spanned by `history` (0 when absent) — drives the "▲ Δ in N min" trend label.
    public let spanMinutes: Int

    public init(metric: MetricKind, value: MeasuredValue, history: [Double] = [], spanMinutes: Int = 0) {
        self.metric = metric
        self.value = value
        self.history = history
        self.spanMinutes = spanMinutes
    }
}

/// One device as the watch needs it: identity, asset, the status the phone computed, plus the
/// last-known operational detail a glanceable device screen shows (battery, connectivity, a few
/// telemetry highlights). Compact and `Codable` so it crosses the WatchConnectivity boundary cheaply.
///
/// `battery` / `connectivity` / `telemetry` are optional-by-default in the initializer so older call
/// sites (and tests) keep compiling; the iPhone always populates them from the same `Device` the app
/// shows.
public struct WatchDeviceSnapshot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: DeviceID
    public let name: String
    public let assetName: String?
    public let status: DeviceStatus
    public let battery: BatteryStatus?
    public let connectivity: ConnectivityStatus
    public let telemetry: [WatchTelemetryHighlight]

    public init(
        id: DeviceID,
        name: String,
        assetName: String?,
        status: DeviceStatus,
        battery: BatteryStatus? = nil,
        connectivity: ConnectivityStatus = .offline,
        telemetry: [WatchTelemetryHighlight] = []
    ) {
        self.id = id
        self.name = name
        self.assetName = assetName
        self.status = status
        self.battery = battery
        self.connectivity = connectivity
        self.telemetry = telemetry
    }

    /// When the device was last heard from, surfaced from connectivity for the "last seen" label.
    public var lastSeenAt: Date? { connectivity.lastSeenAt }
}

/// The lightweight fleet snapshot the **iPhone** builds and sends to the **paired Watch** over
/// WatchConnectivity. It's a pure `Codable` value type (no WatchConnectivity, no UI) so it compiles on
/// every platform and is fully unit-testable.
///
/// It reuses `SnapshotKit`'s `FleetSummary` / `WidgetAlert` (the same read model the widgets and watch UI
/// already speak) plus per-device snapshots, and stamps `lastUpdated` so the receiver can keep the most
/// recent one (latest-wins).
public struct WatchSyncSnapshot: Codable, Sendable, Equatable {
    public let fleet: FleetSummary
    public let devices: [WatchDeviceSnapshot]
    public let criticalAlerts: [WidgetAlert]
    public let lastUpdated: Date

    public init(fleet: FleetSummary, devices: [WatchDeviceSnapshot], criticalAlerts: [WidgetAlert], lastUpdated: Date) {
        self.fleet = fleet
        self.devices = devices
        self.criticalAlerts = criticalAlerts
        self.lastUpdated = lastUpdated
    }

    /// Nothing synced yet — the watch shows its empty state.
    public static let empty = WatchSyncSnapshot(fleet: .empty, devices: [], criticalAlerts: [], lastUpdated: .distantPast)

    /// True once the iPhone has sent a fleet with at least one device.
    public var hasData: Bool { fleet.total > 0 }
}
