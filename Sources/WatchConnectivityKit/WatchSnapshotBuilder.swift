import Foundation
import DomainKit
import PersistenceKit
import SnapshotKit

/// Builds the compact ``WatchSyncSnapshot`` the iPhone sends to the Watch, from the same persisted fleet
/// state the app and widgets show. Pure and deterministic (no WatchConnectivity, no I/O) so iPhone-side
/// construction is unit-testable.
public enum WatchSnapshotBuilder {
    public static func build(from snapshot: PersistedSnapshot, now: Date = Date(), alertLimit: Int = 8) -> WatchSyncSnapshot {
        let alertsByDevice = Dictionary(grouping: snapshot.alerts, by: \.deviceID)
        let assetNames = Dictionary(snapshot.assets.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let devices = snapshot.devices.map { device in
            WatchDeviceSnapshot(
                id: device.id,
                name: device.name,
                assetName: assetNames[device.assetID],
                status: DeviceHealthPolicy.status(
                    connectivity: device.connectivity,
                    activeAlerts: alertsByDevice[device.id] ?? []
                )
            )
        }

        // Reuse SnapshotKit's localized, attention-ordered alert builder, then keep only criticals.
        let criticalAlerts = WidgetAlert.top(from: snapshot, limit: alertLimit).filter { $0.severity == .critical }

        return WatchSyncSnapshot(
            fleet: FleetSummary.make(from: snapshot),
            devices: devices,
            criticalAlerts: criticalAlerts,
            lastUpdated: now
        )
    }
}
