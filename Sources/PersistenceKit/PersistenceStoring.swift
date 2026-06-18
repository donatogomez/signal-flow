import Foundation
import DomainKit

/// The latest persisted state, restored on launch for instant offline-first display.
///
/// It carries the *latest* reading per metric (not the full history) plus last-known device state,
/// active alerts, recent events, and recent insights — everything the UI needs to show meaningful
/// data the moment the app opens, before the live source produces anything new.
public struct PersistedSnapshot: Sendable {
    public let assets: [Asset]
    public let devices: [Device]
    public let latestReadings: [TelemetryReading]
    public let events: [DeviceEvent]
    public let alerts: [Alert]
    public let insights: [InsightRecord]

    public init(
        assets: [Asset],
        devices: [Device],
        latestReadings: [TelemetryReading],
        events: [DeviceEvent],
        alerts: [Alert],
        insights: [InsightRecord]
    ) {
        self.assets = assets
        self.devices = devices
        self.latestReadings = latestReadings
        self.events = events
        self.alerts = alerts
        self.insights = insights
    }
}

/// The persistence port DataKit orchestrates against. It speaks only `DomainKit` entities, so DataKit
/// (and tests) can depend on the abstraction and never touch SwiftData. The implementation
/// (``PersistenceStore``) is a `ModelActor`.
public protocol PersistenceStoring: Sendable {
    /// The latest persisted snapshot for restore-on-launch.
    func loadSnapshot() async throws -> PersistedSnapshot
    /// Inserts or updates the catalog (assets + last-known device state).
    func upsertCatalog(assets: [Asset], devices: [Device]) async throws
    /// Appends telemetry readings (idempotent by id) and enforces retention.
    func appendReadings(_ readings: [TelemetryReading]) async throws
    /// Appends device events (idempotent by id) and enforces retention.
    func appendEvents(_ events: [DeviceEvent]) async throws
    /// Replaces the stored active alerts for a device (covers raise / clear / acknowledge).
    func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) async throws
    /// Appends a generated insight and enforces retention.
    func appendInsight(_ insight: InsightRecord) async throws
}

/// Retention caps that bound the database regardless of how long the app runs.
///
/// Decisions (documented in docs/21):
/// - **Telemetry** is the high-volume table, so we keep the most recent `maxReadingsPerSeries`
///   readings *per device-and-metric* (a rolling window). With ~10 devices × ~3 metrics that's a
///   small, predictable ceiling.
/// - **Events** keep the most recent `maxEventsPerDevice` per device.
/// - **Insights** keep the most recent `maxInsightsPerDevice` per device.
/// - **Alerts** are stored active-only (replaced per device), so they're naturally bounded.
public struct RetentionPolicy: Sendable {
    public var maxReadingsPerSeries: Int
    public var maxEventsPerDevice: Int
    public var maxInsightsPerDevice: Int

    public init(maxReadingsPerSeries: Int = 2_000, maxEventsPerDevice: Int = 1_000, maxInsightsPerDevice: Int = 200) {
        self.maxReadingsPerSeries = maxReadingsPerSeries
        self.maxEventsPerDevice = maxEventsPerDevice
        self.maxInsightsPerDevice = maxInsightsPerDevice
    }

    public static let `default` = RetentionPolicy()
}
