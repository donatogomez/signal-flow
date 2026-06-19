import Foundation
import DomainKit

/// Builders and fake `DomainKit` repositories for feature-model tests. Because the models depend only
/// on the ports, these hand-written fakes give full, deterministic control with no DataKit or
/// simulation involved.
enum FX {
    static func asset(_ name: String, _ kind: AssetKind, id: AssetID, devices: [DeviceID]) throws -> Asset {
        try Asset(id: id, name: name, kind: kind, deviceIDs: devices)
    }

    static func device(
        _ name: String,
        asset: AssetID,
        id: DeviceID = DeviceID(),
        connectivity: ConnectivityStatus.State = .online,
        battery: Double? = nil
    ) throws -> Device {
        try Device(
            id: id, assetID: asset, name: name,
            battery: battery.flatMap { try? BatteryStatus(percentage: $0) },
            connectivity: ConnectivityStatus(state: connectivity)
        )
    }

    static func criticalAlert(device: DeviceID) throws -> Alert {
        Alert(
            deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: .critical,
            message: "Temperature above safe limit",
            observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: 1)
        )
    }

    static func reading(device: DeviceID, _ metric: MetricKind, _ value: Double, unit: MeasurementUnit, at: TimeInterval) throws -> TelemetryReading {
        TelemetryReading(deviceID: device, metric: metric, value: try MeasuredValue(magnitude: value, unit: unit), recordedAt: Date(timeIntervalSince1970: at))
    }

    static func event(device: DeviceID, _ kind: DeviceEvent.Kind, at: TimeInterval) -> DeviceEvent {
        DeviceEvent(deviceID: device, kind: kind, occurredAt: Date(timeIntervalSince1970: at))
    }
}

struct FakeAssetRepository: AssetRepository {
    var byID: [AssetID: Asset] = [:]
    var order: [AssetID] = []
    func allAssets() async throws -> [Asset] { order.compactMap { byID[$0] } }
    func asset(_ id: AssetID) async throws -> Asset {
        guard let asset = byID[id] else { throw DomainError.assetNotFound(id) }
        return asset
    }
}

struct FakeDeviceRepository: DeviceRepository {
    var byAsset: [AssetID: [Device]] = [:]
    var byID: [DeviceID: Device] = [:]
    func devices(inAsset assetID: AssetID) async throws -> [Device] { byAsset[assetID] ?? [] }
    func device(_ id: DeviceID) async throws -> Device {
        guard let device = byID[id] else { throw DomainError.deviceNotFound(id) }
        return device
    }
}

struct FakeAlertRepository: AlertRepository {
    var alertsByDevice: [DeviceID: [Alert]] = [:]
    var rulesByDevice: [DeviceID: [AlertRule]] = [:]
    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert] { alertsByDevice[deviceID] ?? [] }
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule] { rulesByDevice[deviceID] ?? [] }
    func record(_ alert: Alert) async throws {}
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {}
}

struct FakeTelemetryRepository: TelemetryRepository {
    var latest: [DeviceID: [TelemetryReading]] = [:]
    var history: [DeviceID: [MetricKind: [TelemetryReading]]] = [:]
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading] { latest[deviceID] ?? [] }
    func readings(forDevice deviceID: DeviceID, metric: MetricKind, in range: TimeRange) async throws -> [TelemetryReading] {
        (history[deviceID]?[metric] ?? []).filter { range.contains($0.recordedAt) }
    }
}

struct FakeEventRepository: EventRepository {
    var events: [DeviceEvent] = []
    func recentEvents(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent] {
        Array(events.filter { $0.deviceID == deviceID }.prefix(limit))
    }
    func recentEvents(limit: Int) async throws -> [DeviceEvent] { Array(events.prefix(limit)) }
}

struct FakeInsightsProvider: InsightsProviding {
    var stub: DeviceInsight
    func insight(for context: InsightContext) async throws -> DeviceInsight { stub }
}

struct FakeAlertHistoryProvider: AlertHistoryProviding {
    var alerts: [Alert] = []
    func alertHistory(limit: Int) async throws -> [Alert] { Array(alerts.prefix(limit)) }
}

/// A stateful alert repository (actor → Sendable, no `@unchecked`) so acknowledgement actually mutates
/// and a subsequent `activeAlerts` reflects it — needed to test the acknowledge → refresh flow.
actor StatefulAlertRepository: AlertRepository {
    private var byDevice: [DeviceID: [AlertID: Alert]] = [:]

    init(_ alerts: [Alert]) {
        for alert in alerts { byDevice[alert.deviceID, default: [:]][alert.id] = alert }
    }

    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert] {
        Array((byDevice[deviceID] ?? [:]).values).sorted { $0.raisedAt < $1.raisedAt }
    }
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule] { [] }
    func record(_ alert: Alert) async throws { byDevice[alert.deviceID, default: [:]][alert.id] = alert }
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {
        guard let deviceID = byDevice.first(where: { $0.value[id] != nil })?.key,
              var alerts = byDevice[deviceID], var alert = alerts[id] else {
            throw DomainError.alertNotFound(id)
        }
        try alert.acknowledge(at: date)
        alerts[id] = alert
        byDevice[deviceID] = alerts
    }
}

/// An asset repository that always fails — for exercising the error state.
struct ThrowingAssetRepository: AssetRepository {
    func allAssets() async throws -> [Asset] { throw DomainError.offline }
    func asset(_ id: AssetID) async throws -> Asset { throw DomainError.offline }
}

extension DeviceInsight {
    static let sample = DeviceInsight(
        summary: "Holding steady.", anomalyExplanation: "Nothing unusual.",
        recommendation: "No action needed.", severity: .nominal, confidence: 0.5, source: .foundationModel
    )
}
