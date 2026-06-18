import Foundation
import DomainKit
import SimulationKit

/// A device plus the alert rules that govern it — the unit registered with the store.
public struct DeviceCatalogEntry: Sendable {
    public let descriptor: DeviceDescriptor
    public let rules: [AlertRule]

    public init(descriptor: DeviceDescriptor, rules: [AlertRule]) {
        self.descriptor = descriptor
        self.rules = rules
    }
}

/// The data-access core of DataKit: an actor that holds the catalog, the latest device snapshots,
/// bounded telemetry history, device events, and active alerts — and answers all queries in terms of
/// **`DomainKit` types**.
///
/// All mutable state lives here, so concurrent ingestion and reads are race-free by construction with
/// no lock. The `Store*Repository` types are thin adapters that forward to this actor; this is the
/// single place that knows how telemetry becomes a domain snapshot.
public actor InMemoryTelemetryStore {

    // MARK: Records (private; never cross the actor boundary)

    private struct DeviceRecord {
        let descriptor: DeviceDescriptor
        var rules: [AlertRule]
        var latestByMetric: [MetricKind: TelemetryReading] = [:]
        var history: [MetricKind: [TelemetryReading]] = [:]
        var events: [DeviceEvent] = []
        var connectivity: ConnectivityStatus.State = .offline
        var lastSignal: MeasuredValue?
        var lastSeenAt: Date?
        var lastLocation: Location?
        var activeAlerts: [AlertID: Alert] = [:]
        var alertByRule: [AlertRuleID: AlertID] = [:]
    }

    private struct AssetRecord {
        let id: AssetID
        var name: String
        var kind: AssetKind
        var deviceIDs: [DeviceID]
        var location: Location?
    }

    private var devices: [DeviceID: DeviceRecord] = [:]
    private var assets: [AssetID: AssetRecord] = [:]
    private var assetOrder: [AssetID] = []
    private var insightHistory: [DeviceID: [InsightRecord]] = [:]
    private let historyLimit: Int
    private let eventLimit: Int
    private let insightLimit: Int

    public init(historyLimit: Int = 10_000, eventLimit: Int = 500, insightLimit: Int = 100) {
        self.historyLimit = historyLimit
        self.eventLimit = eventLimit
        self.insightLimit = insightLimit
    }

    // MARK: Catalog

    /// Registers devices and their assets (idempotent on device id). Call before ingestion so the
    /// fleet is queryable immediately, even offline and before any telemetry arrives.
    public func register(_ entries: [DeviceCatalogEntry]) {
        for entry in entries {
            let descriptor = entry.descriptor
            if devices[descriptor.id] == nil {
                devices[descriptor.id] = DeviceRecord(descriptor: descriptor, rules: entry.rules)
            }
            if assets[descriptor.assetID] == nil {
                assets[descriptor.assetID] = AssetRecord(
                    id: descriptor.assetID, name: descriptor.name, kind: descriptor.assetKind,
                    deviceIDs: [descriptor.id], location: nil
                )
                assetOrder.append(descriptor.assetID)
            } else if assets[descriptor.assetID]?.deviceIDs.contains(descriptor.id) == false {
                assets[descriptor.assetID]?.deviceIDs.append(descriptor.id)
            }
        }
    }

    /// Loads a restored snapshot into the store **without** re-evaluating rules or emitting events —
    /// these facts were already decided in a previous session. Devices are expected to already exist
    /// (via `register`); any missing one is created with no rules as a defensive fallback.
    public func loadRestoredState(
        assets restoredAssets: [Asset],
        devices restoredDevices: [Device],
        latestReadings: [TelemetryReading],
        events restoredEvents: [DeviceEvent],
        alerts restoredAlerts: [Alert],
        insights restoredInsights: [InsightRecord]
    ) {
        var kindByAsset: [AssetID: AssetKind] = [:]
        for asset in restoredAssets {
            kindByAsset[asset.id] = asset.kind
            if assets[asset.id] == nil {
                assets[asset.id] = AssetRecord(id: asset.id, name: asset.name, kind: asset.kind,
                                               deviceIDs: asset.deviceIDs, location: asset.location)
                assetOrder.append(asset.id)
            } else {
                assets[asset.id]?.location = asset.location
            }
        }

        // Read-modify-write throughout to avoid overlapping access to the `devices` dictionary.
        for device in restoredDevices {
            var record = devices[device.id] ?? DeviceRecord(
                descriptor: DeviceDescriptor(
                    id: device.id, assetID: device.assetID, name: device.name,
                    assetKind: kindByAsset[device.assetID] ?? .warehouse
                ),
                rules: []
            )
            record.connectivity = device.connectivity.state
            record.lastSignal = device.connectivity.signalStrength
            record.lastSeenAt = device.connectivity.lastSeenAt
            record.lastLocation = device.lastKnownLocation
            devices[device.id] = record
        }

        for reading in latestReadings {
            guard var record = devices[reading.deviceID] else { continue }
            record.latestByMetric[reading.metric] = reading
            record.lastSeenAt = latest(record.lastSeenAt, reading.recordedAt)
            devices[reading.deviceID] = record
        }

        for (deviceID, deviceEvents) in Dictionary(grouping: restoredEvents, by: \.deviceID) {
            guard var record = devices[deviceID] else { continue }
            record.events = Array(deviceEvents.sorted { $0.occurredAt < $1.occurredAt }.suffix(eventLimit))
            devices[deviceID] = record
        }

        for alert in restoredAlerts {
            guard var record = devices[alert.deviceID] else { continue }
            record.activeAlerts[alert.id] = alert
            record.alertByRule[alert.ruleID] = alert.id
            devices[alert.deviceID] = record
        }

        for (deviceID, records) in Dictionary(grouping: restoredInsights, by: \.deviceID) {
            insightHistory[deviceID] = Array(records.sorted { $0.createdAt < $1.createdAt }.suffix(insightLimit))
        }
    }

    /// Records a generated insight in the in-memory history (bounded).
    public func recordInsight(_ record: InsightRecord) {
        var list = insightHistory[record.deviceID, default: []]
        list.append(record)
        if list.count > insightLimit { list.removeFirst(list.count - insightLimit) }
        insightHistory[record.deviceID] = list
    }

    public func insightHistory(forDevice id: DeviceID) -> [InsightRecord] {
        (insightHistory[id] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Ingestion

    /// Folds one simulated telemetry item into the store: updates snapshots/history/events and
    /// evaluates alert rules. Unknown devices are ignored.
    public func ingest(_ telemetry: DeviceTelemetry) {
        guard var record = devices[telemetry.deviceID] else { return }
        switch telemetry {
        case .reading(let reading):
            apply(reading, to: &record)
        case .event(let event):
            apply(event, to: &record)
        case .location(_, let location, let date):
            record.lastLocation = location
            record.lastSeenAt = latest(record.lastSeenAt, date)
            assets[record.descriptor.assetID]?.location = location
        }
        devices[telemetry.deviceID] = record
    }

    private func apply(_ reading: TelemetryReading, to record: inout DeviceRecord) {
        record.connectivity = .online
        record.latestByMetric[reading.metric] = reading

        var series = record.history[reading.metric, default: []]
        series.append(reading)
        if series.count > historyLimit { series.removeFirst(series.count - historyLimit) }
        record.history[reading.metric] = series

        record.lastSeenAt = latest(record.lastSeenAt, reading.recordedAt)
        if reading.metric == .signalStrength {
            record.lastSignal = reading.value
            if reading.value.magnitude < -100 { record.connectivity = .degraded }
        }
        evaluateRules(for: reading, in: &record)
    }

    private func apply(_ event: DeviceEvent, to record: inout DeviceRecord) {
        record.events.append(event)
        if record.events.count > eventLimit { record.events.removeFirst(record.events.count - eventLimit) }
        switch event.kind {
        case .disconnected: record.connectivity = .offline
        case .connected: record.connectivity = .online
        default: break
        }
    }

    /// Uses `DomainKit`'s `AlertRule.evaluate` for the breach decision; DataKit only manages the
    /// active-alert *lifecycle* (raise once per breach, clear on recovery).
    private func evaluateRules(for reading: TelemetryReading, in record: inout DeviceRecord) {
        for rule in record.rules where rule.metric == reading.metric {
            if let alert = rule.evaluate(reading.value, on: record.descriptor.id, at: reading.recordedAt) {
                if record.alertByRule[rule.id] == nil {
                    record.activeAlerts[alert.id] = alert
                    record.alertByRule[rule.id] = alert.id
                }
            } else if let activeID = record.alertByRule[rule.id] {
                record.activeAlerts[activeID] = nil
                record.alertByRule[rule.id] = nil
            }
        }
    }

    // MARK: Domain queries

    public func allAssets() throws -> [Asset] {
        try assetOrder.compactMap { assets[$0] }.map(makeAsset)
    }

    public func asset(_ id: AssetID) throws -> Asset {
        guard let record = assets[id] else { throw DomainError.assetNotFound(id) }
        return try makeAsset(record)
    }

    public func devices(inAsset assetID: AssetID) throws -> [Device] {
        guard let asset = assets[assetID] else { throw DomainError.assetNotFound(assetID) }
        return try asset.deviceIDs.compactMap { devices[$0] }.map(makeDevice)
    }

    public func device(_ id: DeviceID) throws -> Device {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return try makeDevice(record)
    }

    public func latestReadings(forDevice id: DeviceID) throws -> [TelemetryReading] {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return record.latestByMetric.values.sorted { $0.metric.displayName < $1.metric.displayName }
    }

    public func readings(forDevice id: DeviceID, metric: MetricKind, in range: TimeRange) throws -> [TelemetryReading] {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return (record.history[metric] ?? [])
            .filter { range.contains($0.recordedAt) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    public func activeAlerts(forDevice id: DeviceID) throws -> [Alert] {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return record.activeAlerts.values.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.raisedAt < $1.raisedAt
        }
    }

    public func rules(forDevice id: DeviceID) throws -> [AlertRule] {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return record.rules
    }

    public func recentEvents(forDevice id: DeviceID, limit: Int) throws -> [DeviceEvent] {
        guard let record = devices[id] else { throw DomainError.deviceNotFound(id) }
        return Array(record.events.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }

    public func recentEvents(limit: Int) -> [DeviceEvent] {
        Array(devices.values.flatMap(\.events).sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }

    public func record(_ alert: Alert) {
        guard var record = devices[alert.deviceID] else { return }
        record.activeAlerts[alert.id] = alert
        record.alertByRule[alert.ruleID] = alert.id
        devices[alert.deviceID] = record
    }

    public func acknowledgeAlert(_ id: AlertID, at date: Date) throws {
        guard let deviceID = devices.first(where: { $0.value.activeAlerts[id] != nil })?.key,
              var record = devices[deviceID], var alert = record.activeAlerts[id]
        else { throw DomainError.alertNotFound(id) }
        try alert.acknowledge(at: date)
        record.activeAlerts[id] = alert
        devices[deviceID] = record
    }

    // MARK: Introspection (for tests / diagnostics)

    public func ingestedReadingCount() -> Int {
        devices.values.reduce(0) { $0 + $1.history.values.reduce(0) { $0 + $1.count } }
    }

    // MARK: Snapshot reconstruction

    private func makeAsset(_ record: AssetRecord) throws -> Asset {
        try Asset(id: record.id, name: record.name, kind: record.kind,
                  deviceIDs: record.deviceIDs, location: record.location)
    }

    private func makeDevice(_ record: DeviceRecord) throws -> Device {
        let metrics = try record.latestByMetric.values
            .sorted { $0.metric.displayName < $1.metric.displayName }
            .map { try MetricDefinition(kind: $0.metric, name: $0.metric.displayName, unit: $0.value.unit) }

        let battery = record.latestByMetric[.batteryLevel]
            .flatMap { try? BatteryStatus(percentage: $0.value.magnitude) }

        let connectivity = ConnectivityStatus(
            state: record.connectivity, signalStrength: record.lastSignal, lastSeenAt: record.lastSeenAt
        )

        return try Device(
            id: record.descriptor.id, assetID: record.descriptor.assetID, name: record.descriptor.name,
            metrics: metrics, battery: battery, connectivity: connectivity,
            lastKnownLocation: record.lastLocation
        )
    }

    private func latest(_ existing: Date?, _ candidate: Date) -> Date {
        guard let existing else { return candidate }
        return Swift.max(existing, candidate)
    }
}
