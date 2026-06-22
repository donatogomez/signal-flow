import Foundation
import DomainKit
import SnapshotKit

/// One device as the watch needs it: identity, asset, and the status the phone computed. Compact and
/// `Codable` so it crosses the WatchConnectivity boundary cheaply.
public struct WatchDeviceSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: DeviceID
    public let name: String
    public let assetName: String?
    public let status: DeviceStatus

    public init(id: DeviceID, name: String, assetName: String?, status: DeviceStatus) {
        self.id = id
        self.name = name
        self.assetName = assetName
        self.status = status
    }
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
