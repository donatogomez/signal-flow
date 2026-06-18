import Foundation
import DomainKit

/// Maps wire DTOs to `DomainKit` entities. This is the boundary that keeps DomainKit ignorant of the
/// network: DTOs never escape NetworkingKit, and every method returns validated domain value types.
///
/// Mapping is throwing because Domain initializers validate their inputs — a malformed payload from a
/// server is rejected here rather than corrupting the domain.
enum DTOMapping {

    enum MappingError: Error { case invalidUUID(String) }

    static func uuid(_ string: String) throws -> UUID {
        guard let uuid = UUID(uuidString: string) else { throw MappingError.invalidUUID(string) }
        return uuid
    }

    // MARK: Enum keys (the wire format)

    static func metricKind(_ key: String) -> MetricKind {
        if key.hasPrefix("custom:") { return .custom(String(key.dropFirst("custom:".count))) }
        switch key {
        case "temperature": return .temperature
        case "humidity": return .humidity
        case "carbonDioxide": return .carbonDioxide
        case "batteryLevel": return .batteryLevel
        case "signalStrength": return .signalStrength
        default: return .custom(key)
        }
    }

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

    static func eventKind(_ key: String) -> DeviceEvent.Kind {
        if key.hasPrefix("custom:") { return .custom(String(key.dropFirst("custom:".count))) }
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

    // MARK: DTO → Domain

    static func measurement(_ dto: MeasurementDTO) throws -> MeasuredValue {
        try MeasuredValue(magnitude: dto.magnitude, unit: MeasurementUnit(rawValue: dto.unit) ?? .unitless)
    }

    static func location(_ dto: LocationDTO?) throws -> Location? {
        guard let dto else { return nil }
        return try Location(latitude: dto.latitude, longitude: dto.longitude, altitude: dto.altitude)
    }

    static func asset(_ dto: AssetDTO) throws -> Asset {
        try Asset(
            id: AssetID(try uuid(dto.id)),
            name: dto.name,
            kind: AssetKind(rawValue: dto.kind) ?? .warehouse,
            deviceIDs: try dto.deviceIds.map { DeviceID(try uuid($0)) },
            location: try location(dto.location)
        )
    }

    static func device(_ dto: DeviceDTO) throws -> Device {
        let signal = try dto.signal.map(measurement)
        return try Device(
            id: DeviceID(try uuid(dto.id)),
            assetID: AssetID(try uuid(dto.assetId)),
            name: dto.name,
            metrics: [],
            battery: nil,
            connectivity: ConnectivityStatus(
                state: ConnectivityStatus.State(rawValue: dto.connectivity) ?? .offline,
                signalStrength: signal,
                lastSeenAt: dto.lastSeenAt
            ),
            lastKnownLocation: try location(dto.location)
        )
    }

    static func reading(_ dto: TelemetryReadingDTO) throws -> TelemetryReading {
        try TelemetryReading(
            id: ReadingID(try uuid(dto.id)),
            deviceID: DeviceID(try uuid(dto.deviceId)),
            metric: metricKind(dto.metric),
            value: measurement(dto.value),
            recordedAt: dto.recordedAt
        )
    }

    static func event(_ dto: DeviceEventDTO) throws -> DeviceEvent {
        DeviceEvent(
            id: EventID(try uuid(dto.id)),
            deviceID: DeviceID(try uuid(dto.deviceId)),
            kind: eventKind(dto.kind),
            occurredAt: dto.occurredAt,
            detail: dto.detail
        )
    }

    static func alert(_ dto: AlertDTO) throws -> Alert {
        try Alert(
            id: AlertID(try uuid(dto.id)),
            deviceID: DeviceID(try uuid(dto.deviceId)),
            ruleID: AlertRuleID(try uuid(dto.ruleId)),
            metric: metricKind(dto.metric),
            severity: AlertSeverity(rawValue: dto.severity) ?? .warning,
            message: dto.message,
            observedValue: measurement(dto.observedValue),
            raisedAt: dto.raisedAt,
            acknowledgedAt: dto.acknowledgedAt
        )
    }

    static func insight(_ dto: InsightRecordDTO) throws -> InsightRecord {
        InsightRecord(
            id: ReadingID(try uuid(dto.id)),
            deviceID: DeviceID(try uuid(dto.deviceId)),
            metric: metricKind(dto.metric),
            insight: DeviceInsight(
                summary: dto.summary,
                anomalyExplanation: dto.anomalyExplanation,
                recommendation: dto.recommendation,
                severity: InsightSeverity(rawValue: dto.severity) ?? .nominal,
                confidence: dto.confidence,
                source: InsightSource(rawValue: dto.source) ?? .deterministic
            ),
            createdAt: dto.createdAt
        )
    }
}
