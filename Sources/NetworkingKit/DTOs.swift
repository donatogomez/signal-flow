import Foundation

// Wire-format representations of the API's resources. These are the *only* place JSON shapes live;
// they are mapped to DomainKit entities by `DTOMapping`, so DomainKit never knows DTOs exist.
// Dates are ISO-8601 (configured on the decoder); ids are UUID strings; enums are string keys.

struct LocationDTO: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
}

struct MeasurementDTO: Codable, Sendable {
    let magnitude: Double
    let unit: String
}

struct AssetDTO: Codable, Sendable {
    let id: String
    let name: String
    let kind: String
    let deviceIds: [String]
    let location: LocationDTO?
}

struct DeviceDTO: Codable, Sendable {
    let id: String
    let assetId: String
    let name: String
    let connectivity: String
    let signal: MeasurementDTO?
    let lastSeenAt: Date?
    let location: LocationDTO?
}

struct TelemetryReadingDTO: Codable, Sendable {
    let id: String
    let deviceId: String
    let metric: String
    let value: MeasurementDTO
    let recordedAt: Date
}

struct DeviceEventDTO: Codable, Sendable {
    let id: String
    let deviceId: String
    let kind: String
    let detail: String?
    let occurredAt: Date
}

struct AlertDTO: Codable, Sendable {
    let id: String
    let deviceId: String
    let ruleId: String
    let metric: String
    let severity: String
    let message: String
    let observedValue: MeasurementDTO
    let raisedAt: Date
    let acknowledgedAt: Date?
}

struct InsightRecordDTO: Codable, Sendable {
    let id: String
    let deviceId: String
    let metric: String
    let summary: String
    let anomalyExplanation: String
    let recommendation: String
    let severity: String
    let source: String
    let confidence: Double
    let createdAt: Date
}
