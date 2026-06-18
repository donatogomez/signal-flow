import Foundation
import DomainKit

/// Translates between SwiftData `@Model` records and `DomainKit` entities.
///
/// This is the boundary that keeps `DomainKit` ignorant of SwiftData: records never escape
/// PersistenceKit, and the Domain only ever sees its own value types. Domain enums are encoded as
/// stable strings so the schema stays primitive and migration-friendly.
enum Mapping {

    enum MappingError: Error { case invalidUUID(String) }

    static func uuid(_ string: String) throws -> UUID {
        guard let uuid = UUID(uuidString: string) else { throw MappingError.invalidUUID(string) }
        return uuid
    }

    // MARK: Metric & event codecs

    static func metricKey(_ metric: MetricKind) -> String {
        switch metric {
        case .temperature: "temperature"
        case .humidity: "humidity"
        case .carbonDioxide: "carbonDioxide"
        case .batteryLevel: "batteryLevel"
        case .signalStrength: "signalStrength"
        case .custom(let key): "custom:\(key)"
        }
    }

    static func metricKind(_ key: String) -> MetricKind {
        if let custom = key.dropPrefix("custom:") { return .custom(custom) }
        switch key {
        case "temperature": return .temperature
        case "humidity": return .humidity
        case "carbonDioxide": return .carbonDioxide
        case "batteryLevel": return .batteryLevel
        case "signalStrength": return .signalStrength
        default: return .custom(key)
        }
    }

    static func eventKey(_ kind: DeviceEvent.Kind) -> String {
        switch kind {
        case .doorOpened: "doorOpened"
        case .doorClosed: "doorClosed"
        case .connected: "connected"
        case .disconnected: "disconnected"
        case .powerLost: "powerLost"
        case .powerRestored: "powerRestored"
        case .custom(let key): "custom:\(key)"
        }
    }

    static func eventKind(_ key: String) -> DeviceEvent.Kind {
        if let custom = key.dropPrefix("custom:") { return .custom(custom) }
        switch key {
        case "doorOpened": return .doorOpened
        case "doorClosed": return .doorClosed
        case "connected": return .connected
        case "disconnected": return .disconnected
        case "powerLost": return .powerLost
        case "powerRestored": return .powerRestored
        default: return .custom(key)
        }
    }

    // MARK: Domain → Record

    static func record(_ asset: Asset) -> AssetRecord {
        AssetRecord(
            id: asset.id.rawValue.uuidString,
            name: asset.name,
            kindRaw: asset.kind.rawValue,
            deviceIDs: asset.deviceIDs.map { $0.rawValue.uuidString },
            latitude: asset.location?.latitude,
            longitude: asset.location?.longitude,
            altitude: asset.location?.altitude
        )
    }

    static func record(_ device: Device) -> DeviceRecord {
        DeviceRecord(
            id: device.id.rawValue.uuidString,
            assetID: device.assetID.rawValue.uuidString,
            name: device.name,
            connectivityRaw: device.connectivity.state.rawValue,
            signalMagnitude: device.connectivity.signalStrength?.magnitude,
            signalUnitRaw: device.connectivity.signalStrength?.unit.rawValue,
            lastSeenAt: device.connectivity.lastSeenAt,
            latitude: device.lastKnownLocation?.latitude,
            longitude: device.lastKnownLocation?.longitude,
            altitude: device.lastKnownLocation?.altitude
        )
    }

    static func record(_ reading: TelemetryReading) -> ReadingRecord {
        ReadingRecord(
            id: reading.id.rawValue.uuidString,
            deviceID: reading.deviceID.rawValue.uuidString,
            metricKey: metricKey(reading.metric),
            unitRaw: reading.value.unit.rawValue,
            magnitude: reading.value.magnitude,
            recordedAt: reading.recordedAt
        )
    }

    static func record(_ event: DeviceEvent) -> EventRecord {
        EventRecord(
            id: event.id.rawValue.uuidString,
            deviceID: event.deviceID.rawValue.uuidString,
            kindKey: eventKey(event.kind),
            detail: event.detail,
            occurredAt: event.occurredAt
        )
    }

    static func record(_ alert: Alert) -> AlertRecord {
        AlertRecord(
            id: alert.id.rawValue.uuidString,
            deviceID: alert.deviceID.rawValue.uuidString,
            ruleID: alert.ruleID.rawValue.uuidString,
            metricKey: metricKey(alert.metric),
            severityRaw: alert.severity.rawValue,
            message: alert.message,
            observedMagnitude: alert.observedValue.magnitude,
            observedUnitRaw: alert.observedValue.unit.rawValue,
            raisedAt: alert.raisedAt,
            acknowledgedAt: alert.acknowledgedAt
        )
    }

    static func record(_ insight: InsightRecord) -> InsightHistoryRecord {
        InsightHistoryRecord(
            id: insight.id.rawValue.uuidString,
            deviceID: insight.deviceID.rawValue.uuidString,
            metricKey: metricKey(insight.metric),
            summary: insight.insight.summary,
            anomalyExplanation: insight.insight.anomalyExplanation,
            recommendation: insight.insight.recommendation,
            severityRaw: insight.insight.severity.rawValue,
            sourceRaw: insight.insight.source.rawValue,
            confidence: insight.insight.confidence,
            createdAt: insight.createdAt
        )
    }

    // MARK: Record → Domain

    static func asset(_ record: AssetRecord) throws -> Asset {
        try Asset(
            id: AssetID(try uuid(record.id)),
            name: record.name,
            kind: AssetKind(rawValue: record.kindRaw) ?? .warehouse,
            deviceIDs: try record.deviceIDs.map { DeviceID(try uuid($0)) },
            location: try location(record.latitude, record.longitude, record.altitude)
        )
    }

    static func device(_ record: DeviceRecord) throws -> Device {
        let signal: MeasuredValue? = try {
            guard let magnitude = record.signalMagnitude,
                  let unit = record.signalUnitRaw.flatMap(MeasurementUnit.init(rawValue:)) else { return nil }
            return try MeasuredValue(magnitude: magnitude, unit: unit)
        }()
        let connectivity = ConnectivityStatus(
            state: ConnectivityStatus.State(rawValue: record.connectivityRaw) ?? .offline,
            signalStrength: signal,
            lastSeenAt: record.lastSeenAt
        )
        return try Device(
            id: DeviceID(try uuid(record.id)),
            assetID: AssetID(try uuid(record.assetID)),
            name: record.name,
            metrics: [],
            battery: nil,
            connectivity: connectivity,
            lastKnownLocation: try location(record.latitude, record.longitude, record.altitude)
        )
    }

    static func reading(_ record: ReadingRecord) throws -> TelemetryReading {
        try TelemetryReading(
            id: ReadingID(try uuid(record.id)),
            deviceID: DeviceID(try uuid(record.deviceID)),
            metric: metricKind(record.metricKey),
            value: MeasuredValue(magnitude: record.magnitude, unit: MeasurementUnit(rawValue: record.unitRaw) ?? .unitless),
            recordedAt: record.recordedAt
        )
    }

    static func event(_ record: EventRecord) throws -> DeviceEvent {
        DeviceEvent(
            id: EventID(try uuid(record.id)),
            deviceID: DeviceID(try uuid(record.deviceID)),
            kind: eventKind(record.kindKey),
            occurredAt: record.occurredAt,
            detail: record.detail
        )
    }

    static func alert(_ record: AlertRecord) throws -> Alert {
        try Alert(
            id: AlertID(try uuid(record.id)),
            deviceID: DeviceID(try uuid(record.deviceID)),
            ruleID: AlertRuleID(try uuid(record.ruleID)),
            metric: metricKind(record.metricKey),
            severity: AlertSeverity(rawValue: record.severityRaw) ?? .warning,
            message: record.message,
            observedValue: MeasuredValue(magnitude: record.observedMagnitude, unit: MeasurementUnit(rawValue: record.observedUnitRaw) ?? .unitless),
            raisedAt: record.raisedAt,
            acknowledgedAt: record.acknowledgedAt
        )
    }

    static func insight(_ record: InsightHistoryRecord) throws -> InsightRecord {
        InsightRecord(
            id: ReadingID(try uuid(record.id)),
            deviceID: DeviceID(try uuid(record.deviceID)),
            metric: metricKind(record.metricKey),
            insight: DeviceInsight(
                summary: record.summary,
                anomalyExplanation: record.anomalyExplanation,
                recommendation: record.recommendation,
                severity: InsightSeverity(rawValue: record.severityRaw) ?? .nominal,
                confidence: record.confidence,
                source: InsightSource(rawValue: record.sourceRaw) ?? .deterministic
            ),
            createdAt: record.createdAt
        )
    }

    private static func location(_ latitude: Double?, _ longitude: Double?, _ altitude: Double?) throws -> Location? {
        guard let latitude, let longitude else { return nil }
        return try Location(latitude: latitude, longitude: longitude, altitude: altitude)
    }
}

private extension String {
    /// Returns the remainder after `prefix`, or `nil` if the prefix isn't present.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
