import Foundation
import DomainKit
import PersistenceKit
import SnapshotKit

/// Builds the compact ``WatchSyncSnapshot`` the iPhone sends to the Watch, from the same persisted fleet
/// state the app and widgets show. Pure and deterministic (no WatchConnectivity, no I/O) so iPhone-side
/// construction is unit-testable.
public enum WatchSnapshotBuilder {
    /// Number of recent points kept for a device's mini-trend sparkline.
    public static let trendPointCount = 8

    /// - Parameter history: recent readings (oldest→newest) for each device's **primary** metric, used to
    ///   build its sparkline + trend delta. The iPhone fetches these; the builder stays pure.
    public static func build(
        from snapshot: PersistedSnapshot,
        now: Date = Date(),
        alertLimit: Int = 8,
        history: [DeviceID: [TelemetryReading]] = [:]
    ) -> WatchSyncSnapshot {
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
                telemetry: highlights(from: readingsByDevice[device.id] ?? [], history: history[device.id] ?? [])
            )
        }

        // Reuse SnapshotKit's localized, attention-ordered alert builder, then keep only criticals.
        // Send the actionable alerts — warnings *and* criticals — so the watch's inbox has the same
        // attention-worthy set the operator sees (info-level notices stay on the phone).
        let criticalAlerts = WidgetAlert.top(from: snapshot, limit: alertLimit).filter { $0.severity >= .warning }

        return WatchSyncSnapshot(
            fleet: FleetSummary.make(from: snapshot),
            devices: devices,
            criticalAlerts: criticalAlerts,
            lastUpdated: now
        )
    }

    /// The highest-priority metric present in a device's readings (the one a glance should feature and
    /// trend). `public` so the iPhone can decide which metric's history to fetch.
    public static func primaryMetric(of readings: [TelemetryReading]) -> MetricKind? {
        Set(readings.map(\.metric)).min { priority($0) < priority($1) }
    }

    /// The few telemetry highlights worth a glance: the newest reading per metric, ordered by a stable
    /// metric priority, capped so the watch screen stays uncluttered. `history` may mix metrics; each
    /// highlight is attached its own metric's recent series (oldest→newest magnitudes) + the minutes it
    /// spans, so several metrics (e.g. temperature **and** humidity) can each show a trend.
    static func highlights(from readings: [TelemetryReading], history: [TelemetryReading] = [], limit: Int = 3) -> [WatchTelemetryHighlight] {
        let newestPerMetric = Dictionary(readings.map { ($0.metric, $0) }, uniquingKeysWith: { a, b in
            a.recordedAt >= b.recordedAt ? a : b
        })
        let historyByMetric = Dictionary(grouping: history, by: \.metric)

        return newestPerMetric.values
            .sorted { priority($0.metric) < priority($1.metric) }
            .prefix(limit)
            .map { reading in
                let series = (historyByMetric[reading.metric] ?? [])
                    .sorted { $0.recordedAt < $1.recordedAt }
                    .suffix(trendPointCount)
                guard series.count >= 2, let first = series.first, let last = series.last else {
                    return WatchTelemetryHighlight(metric: reading.metric, value: reading.value)
                }
                let span = Int((last.recordedAt.timeIntervalSince(first.recordedAt) / 60).rounded())
                return WatchTelemetryHighlight(
                    metric: reading.metric,
                    value: reading.value,
                    history: series.map(\.value.magnitude),
                    spanMinutes: max(span, 0)
                )
            }
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
