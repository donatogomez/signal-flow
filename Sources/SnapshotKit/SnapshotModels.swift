import Foundation
import DomainKit
import PersistenceKit

/// Aggregated fleet health for glance surfaces (widgets, App Intents) — a pure value type derived
/// deterministically from a ``PersistedSnapshot``. Counts are bucketed by ``DeviceStatus`` so they match
/// exactly what the app shows, because both go through the same ``DeviceHealthPolicy``.
public struct FleetSummary: Sendable, Equatable, Codable {
    public let online: Int      // DeviceStatus.nominal — connected and healthy
    public let warning: Int     // DeviceStatus.warning
    public let critical: Int    // DeviceStatus.critical
    public let offline: Int     // DeviceStatus.offline
    /// Freshness of the underlying data: the newest reading time we have, if any.
    public let lastUpdated: Date?

    public init(online: Int, warning: Int, critical: Int, offline: Int, lastUpdated: Date?) {
        self.online = online
        self.warning = warning
        self.critical = critical
        self.offline = offline
        self.lastUpdated = lastUpdated
    }

    public static let empty = FleetSummary(online: 0, warning: 0, critical: 0, offline: 0, lastUpdated: nil)

    public var total: Int { online + warning + critical + offline }

    /// Buckets every device by the status the app would show it as, then records data freshness.
    public static func make(from snapshot: PersistedSnapshot) -> FleetSummary {
        let alertsByDevice = Dictionary(grouping: snapshot.alerts, by: \.deviceID)

        var online = 0, warning = 0, critical = 0, offline = 0
        for device in snapshot.devices {
            switch DeviceHealthPolicy.status(
                connectivity: device.connectivity,
                activeAlerts: alertsByDevice[device.id] ?? []
            ) {
            case .nominal: online += 1
            case .warning: warning += 1
            case .critical: critical += 1
            case .offline: offline += 1
            }
        }

        let lastUpdated = snapshot.latestReadings.map(\.recordedAt).max()
        return FleetSummary(online: online, warning: warning, critical: critical, offline: offline, lastUpdated: lastUpdated)
    }
}

/// One alert as a glance surface needs it: just the device name, severity, and message — pre-joined so
/// widgets and intents render without touching repositories.
public struct WidgetAlert: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: AlertID
    public let deviceName: String
    public let severity: AlertSeverity
    public let message: String
    public let raisedAt: Date

    public init(id: AlertID, deviceName: String, severity: AlertSeverity, message: String, raisedAt: Date) {
        self.id = id
        self.deviceName = deviceName
        self.severity = severity
        self.message = message
        self.raisedAt = raisedAt
    }

    /// The most pressing active alerts, joined with device names and capped at `limit`.
    ///
    /// Selection is deterministic: **unacknowledged before acknowledged, then most severe, then most
    /// recent** — the same attention ordering the in-app Alerts screen uses.
    public static func top(from snapshot: PersistedSnapshot, limit: Int) -> [WidgetAlert] {
        let names = Dictionary(snapshot.devices.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        return snapshot.alerts
            .sorted(by: ordering)
            .prefix(limit)
            .map { alert in
                WidgetAlert(
                    id: alert.id,
                    deviceName: names[alert.deviceID] ?? String(localized: "Unknown device", bundle: .module),
                    severity: alert.severity,
                    message: AlertText.message(metric: alert.metric, value: alert.observedValue),
                    raisedAt: alert.raisedAt
                )
            }
    }

    static func ordering(_ a: Alert, _ b: Alert) -> Bool {
        if a.isAcknowledged != b.isAcknowledged { return !a.isAcknowledged }
        if a.severity != b.severity { return a.severity > b.severity }
        return a.raisedAt > b.raisedAt
    }
}

/// The full read model assembled from a persisted snapshot, shared by widgets and intents.
public struct WidgetData: Sendable, Equatable {
    public let fleet: FleetSummary
    public let alerts: [WidgetAlert]
    /// When this data was assembled — drives the "updated" label.
    public let generatedAt: Date

    public init(fleet: FleetSummary, alerts: [WidgetAlert], generatedAt: Date) {
        self.fleet = fleet
        self.alerts = alerts
        self.generatedAt = generatedAt
    }

    public static let placeholder = WidgetData(
        fleet: FleetSummary(online: 8, warning: 1, critical: 1, offline: 0, lastUpdated: nil),
        alerts: [],
        generatedAt: .distantPast
    )

    /// A real-but-empty payload used when persisted state can't be read (first launch, no App Group).
    public static func empty(now: Date) -> WidgetData {
        WidgetData(fleet: .empty, alerts: [], generatedAt: now)
    }
}
