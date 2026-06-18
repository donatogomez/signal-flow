import Foundation
import DomainKit

/// Domain-entity builders for persistence tests.
enum PX {
    static func asset(_ name: String = "Greenhouse A", kind: AssetKind = .greenhouse, id: AssetID = AssetID(), devices: [DeviceID] = []) throws -> Asset {
        try Asset(id: id, name: name, kind: kind, deviceIDs: devices, location: try Location(latitude: 41.4, longitude: 2.1))
    }

    static func device(_ name: String = "Reefer 12", id: DeviceID = DeviceID(), asset: AssetID = AssetID(), state: ConnectivityStatus.State = .online) throws -> Device {
        try Device(
            id: id, assetID: asset, name: name,
            connectivity: ConnectivityStatus(state: state, signalStrength: try MeasuredValue(magnitude: -72, unit: .decibelMilliwatts), lastSeenAt: Date(timeIntervalSince1970: 1_000)),
            lastKnownLocation: try Location(latitude: 41.4, longitude: 2.1)
        )
    }

    static func reading(device: DeviceID, _ metric: MetricKind = .temperature, _ value: Double, unit: MeasurementUnit = .celsius, at: TimeInterval, id: ReadingID = ReadingID()) throws -> TelemetryReading {
        TelemetryReading(id: id, deviceID: device, metric: metric, value: try MeasuredValue(magnitude: value, unit: unit), recordedAt: Date(timeIntervalSince1970: at))
    }

    static func event(device: DeviceID, _ kind: DeviceEvent.Kind = .doorOpened, at: TimeInterval, detail: String? = "x") -> DeviceEvent {
        DeviceEvent(deviceID: device, kind: kind, occurredAt: Date(timeIntervalSince1970: at), detail: detail)
    }

    static func alert(device: DeviceID, severity: AlertSeverity = .critical, acknowledged: Bool = false) throws -> Alert {
        var alert = Alert(
            deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: severity,
            message: "Too hot", observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: 5)
        )
        if acknowledged { try alert.acknowledge(at: Date(timeIntervalSince1970: 6)) }
        return alert
    }

    static func insightRecord(device: DeviceID, at: TimeInterval = 10) -> InsightRecord {
        InsightRecord(
            deviceID: device, metric: .temperature,
            insight: DeviceInsight(summary: "s", anomalyExplanation: "a", recommendation: "r", severity: .watch, confidence: 0.6, source: .foundationModel),
            createdAt: Date(timeIntervalSince1970: at)
        )
    }
}
