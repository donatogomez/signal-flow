/// The semantic kind of a telemetry metric.
///
/// The `custom` case lets new sensor types be introduced without changing the model — the fleet,
/// charts, and alert engine are all generic over `MetricKind`, so "a new kind of number" needs no
/// schema migration.
public enum MetricKind: Hashable, Sendable, Codable {
    case temperature
    case humidity
    case carbonDioxide
    case batteryLevel
    case signalStrength
    case custom(String)

    /// The unit this metric is conventionally measured in. A `MetricDefinition` may override it.
    public var canonicalUnit: MeasurementUnit {
        switch self {
        case .temperature: .celsius
        case .humidity: .percent
        case .carbonDioxide: .partsPerMillion
        case .batteryLevel: .percent
        case .signalStrength: .decibelMilliwatts
        case .custom: .unitless
        }
    }

    /// Human-readable label used in alert messages and summaries.
    public var displayName: String {
        switch self {
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .carbonDioxide: "CO₂"
        case .batteryLevel: "Battery level"
        case .signalStrength: "Signal strength"
        case .custom(let key): key
        }
    }
}
