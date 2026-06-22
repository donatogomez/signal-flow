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
        let readingsByDevice = Dictionary(grouping: snapshot.latestReadings, by: \.deviceID)

        let devices = snapshot.devices.map { device in
            WatchDeviceSnapshot(
                id: device.id,
                name: device.name,
                assetName: assetNames[device.assetID],
                status: DeviceHealthPolicy.status(
                    connectivity: device.connectivity,
                    activeAlerts: alertsByDevice[device.id] ?? []
                ),
                battery: device.battery,
                connectivity: device.connectivity,
                telemetry: highlights(from: readingsByDevice[device.id] ?? [])
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

    /// The few telemetry highlights worth a glance: the newest reading per metric, ordered by a stable
    /// metric priority (the environmental signals first), capped so the watch screen stays uncluttered.
    static func highlights(from readings: [TelemetryReading], limit: Int = 3) -> [WatchTelemetryHighlight] {
        let newestPerMetric = Dictionary(readings.map { ($0.metric, $0) }, uniquingKeysWith: { a, b in
            a.recordedAt >= b.recordedAt ? a : b
        })
        return newestPerMetric.values
            .sorted { priority($0.metric) < priority($1.metric) }
            .prefix(limit)
            .map { WatchTelemetryHighlight(metric: $0.metric, value: $0.value) }
    }

    private static func priority(_ metric: MetricKind) -> Int {
        switch metric {
        case .temperature: 0
        case .humidity: 1
        case .carbonDioxide: 2
        case .signalStrength: 3
        case .batteryLevel: 4
        case .custom: 5
        }
    }
}
