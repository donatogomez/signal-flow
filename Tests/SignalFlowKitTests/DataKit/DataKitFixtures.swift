import Foundation
import DomainKit
import SimulationKit
import DataKit

/// Builders for DataKit tests. Uses the public surface of DataKit, SimulationKit, and DomainKit only.
enum DataKitFixtures {
    static let origin = Date(timeIntervalSince1970: 1_700_000_000)

    static func descriptor(
        id: DeviceID = DeviceID(),
        assetID: AssetID = AssetID(),
        name: String = "Reefer 12",
        kind: AssetKind = .refrigeratedTruck
    ) -> DeviceDescriptor {
        DeviceDescriptor(id: id, assetID: assetID, name: name, assetKind: kind)
    }

    static func entry(_ descriptor: DeviceDescriptor, rules: [AlertRule] = []) -> DeviceCatalogEntry {
        DeviceCatalogEntry(descriptor: descriptor, rules: rules)
    }

    static func reading(
        deviceID: DeviceID,
        _ metric: MetricKind,
        _ magnitude: Double,
        unit: MeasurementUnit = .celsius,
        at offset: TimeInterval = 0
    ) throws -> TelemetryReading {
        TelemetryReading(
            deviceID: deviceID,
            metric: metric,
            value: try MeasuredValue(magnitude: magnitude, unit: unit),
            recordedAt: origin.addingTimeInterval(offset)
        )
    }

    static func event(deviceID: DeviceID, _ kind: DeviceEvent.Kind, at offset: TimeInterval = 0) -> DeviceEvent {
        DeviceEvent(deviceID: deviceID, kind: kind, occurredAt: origin.addingTimeInterval(offset))
    }

    static func temperatureRule(max: Double, severity: AlertSeverity = .critical) throws -> AlertRule {
        try AlertRule(name: "Max temperature", metric: .temperature, threshold: try Threshold(upperBound: max), severity: severity)
    }

    static func wideRange() throws -> TimeRange {
        try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 4_000_000_000))
    }
}
