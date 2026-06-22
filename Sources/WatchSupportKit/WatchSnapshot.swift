import Foundation
import SnapshotKit
import WatchConnectivityKit

/// The read model the watch app renders, derived from the persisted snapshot.
///
/// `hasData` distinguishes "the iPhone app hasn't populated the shared store yet" (empty state) from
/// "there is a fleet, and it happens to be all-healthy". The watch never computes any of this itself —
/// it's the same `SnapshotKit` aggregation the widgets and App Intents use.
public struct WatchSnapshot: Sendable, Equatable {
    public let fleet: FleetSummary
    public let alerts: [WidgetAlert]
    /// Per-device snapshots, present when the data came over WatchConnectivity (the App-Group reader can't
    /// supply them). Drives the Devices list and Device Snapshot screen; empty otherwise.
    public let devices: [WatchDeviceSnapshot]
    public let hasData: Bool

    public init(fleet: FleetSummary, alerts: [WidgetAlert], devices: [WatchDeviceSnapshot] = [], hasData: Bool) {
        self.fleet = fleet
        self.alerts = alerts
        self.devices = devices
        self.hasData = hasData
    }

    /// No fleet has been persisted yet — the iPhone app needs to run first.
    public static let empty = WatchSnapshot(fleet: .empty, alerts: [], devices: [], hasData: false)

    /// Builds a watch snapshot from a `SnapshotKit` read model. A fleet with no devices is treated as
    /// "no data yet" so the UI can show its empty state. The App-Group read model carries no per-device
    /// snapshots, so `devices` is empty on this path (the live watch path uses the synced provider below).
    public static func from(_ data: WidgetData) -> WatchSnapshot {
        WatchSnapshot(fleet: data.fleet, alerts: data.alerts, devices: [], hasData: data.fleet.total > 0)
    }

    /// The freshest data time, if known — drives the "Updated" label on the Fleet Summary.
    public var lastUpdated: Date? { fleet.lastUpdated }
}

/// Reads a ``WatchSnapshot`` from persisted state. Injectable so tests can drive it from an in-memory store.
public protocol WatchSnapshotProviding: Sendable {
    func load() async -> WatchSnapshot
}

/// Live provider: reads the shared App Group store through `SnapshotKit`'s reader (PersistenceKit →
/// SwiftData). It **never** starts simulation or live ingestion — it only observes what the iPhone app
/// has already persisted. If the store can't be read, it returns ``WatchSnapshot/empty``.
public struct PersistedWatchSnapshotProvider: WatchSnapshotProviding {
    private let makeReader: @Sendable () throws -> WidgetSnapshotReader

    public init() {
        self.makeReader = { try WidgetSnapshotReader.shared() }
    }

    /// Test seam: read through an injected reader (e.g. one over an in-memory `PersistenceStore`).
    public init(reader: WidgetSnapshotReader) {
        self.makeReader = { reader }
    }

    public func load() async -> WatchSnapshot {
        guard let reader = try? makeReader(), let data = try? await reader.read() else {
            return .empty
        }
        return .from(data)
    }
}

/// The real watch provider: reads the latest snapshot **synced from the iPhone** over WatchConnectivity
/// and persisted locally by ``WatchConnectivityKit/WatchSyncSnapshotStore``. This is what makes the watch
/// show live fleet data — App Groups don't cross the iPhone/Watch boundary (see docs/27), so the synced
/// snapshot is the watch's source of truth. No data yet ⇒ ``WatchSnapshot/empty`` (the empty state).
public struct SyncedWatchSnapshotProvider: WatchSnapshotProviding {
    private let store: WatchSyncSnapshotStore

    public init(store: WatchSyncSnapshotStore = WatchSyncSnapshotStore()) {
        self.store = store
    }

    public func load() async -> WatchSnapshot {
        guard let synced = store.load(), synced.hasData else {
            SyncLog.log("watch: SyncedProvider.load — no synced data (showing empty state)")
            return .empty
        }
        SyncLog.log("watch: SyncedProvider.load — devices=\(synced.devices.count) criticalAlerts=\(synced.criticalAlerts.count) fleetTotal=\(synced.fleet.total)")
        return WatchSnapshot(fleet: synced.fleet, alerts: synced.criticalAlerts, devices: synced.devices, hasData: true)
    }
}
