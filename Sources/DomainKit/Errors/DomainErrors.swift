import Foundation

/// Failures that arise while *constructing* domain values from untrusted input.
///
/// These are thrown by validating initializers, so an invalid value object simply cannot exist.
public enum ValidationError: Error, Hashable, Sendable {
    case emptyName(context: String)
    case invalidThreshold(reason: String)
    case invalidTimeRange(start: Date, end: Date)
    case nonFiniteMeasurement(Double)
    case impossibleBatteryPercentage(Double)
    case invalidCoordinate(latitude: Double, longitude: Double)
    case valueOutOfRange(value: Double, range: ClosedRange<Double>)
    case unitMismatch(expected: MeasurementUnit, actual: MeasurementUnit)
}

extension ValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyName(let context):
            "\(context) name must not be empty"
        case .invalidThreshold(let reason):
            "Invalid threshold: \(reason)"
        case .invalidTimeRange(let start, let end):
            "Invalid time range: start \(start) is after end \(end)"
        case .nonFiniteMeasurement(let value):
            "Measurement \(value) is not a finite number"
        case .impossibleBatteryPercentage(let value):
            "Battery percentage \(value) is outside 0…100"
        case .invalidCoordinate(let latitude, let longitude):
            "Coordinate (\(latitude), \(longitude)) is off the Earth"
        case .valueOutOfRange(let value, let range):
            "Value \(value) is outside the metric's valid range \(range)"
        case .unitMismatch(let expected, let actual):
            "Unit mismatch: expected \(expected.rawValue), got \(actual.rawValue)"
        }
    }
}

/// Failures that arise while *operating* on the domain — lookups, lifecycle transitions, and the
/// boundaries to outer services. Validation failures are wrapped via ``validation(_:)``.
public enum DomainError: Error, Hashable, Sendable {
    case assetNotFound(AssetID)
    case deviceNotFound(DeviceID)
    case metricNotFound(MetricID)
    case alertNotFound(AlertID)
    case ruleNotFound(AlertRuleID)
    case alertAlreadyAcknowledged(AlertID)
    case insufficientData
    case insightUnavailable(reason: String)
    case offline
    case validation(ValidationError)
}

extension DomainError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .assetNotFound(let id): "Asset \(id) not found"
        case .deviceNotFound(let id): "Device \(id) not found"
        case .metricNotFound(let id): "Metric \(id) not found"
        case .alertNotFound(let id): "Alert \(id) not found"
        case .ruleNotFound(let id): "Alert rule \(id) not found"
        case .alertAlreadyAcknowledged(let id): "Alert \(id) is already acknowledged"
        case .insufficientData: "Not enough data to complete the operation"
        case .insightUnavailable(let reason): "Insight unavailable: \(reason)"
        case .offline: "The operation requires connectivity"
        case .validation(let error): error.description
        }
    }
}
