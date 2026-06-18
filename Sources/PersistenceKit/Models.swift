import Foundation
import SwiftData

// SwiftData @Model classes — the persistent representation. These are reference types and are *not*
// Sendable; they never leave PersistenceKit's ModelActor. Everything stored is a primitive so the
// schema is simple and migration-friendly; domain enums are encoded as strings via `Mapping`.

@Model
final class AssetRecord {
    @Attribute(.unique) var id: String
    var name: String
    var kindRaw: String
    var deviceIDs: [String]
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?

    init(id: String, name: String, kindRaw: String, deviceIDs: [String], latitude: Double?, longitude: Double?, altitude: Double?) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.deviceIDs = deviceIDs
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

@Model
final class DeviceRecord {
    @Attribute(.unique) var id: String
    var assetID: String
    var name: String
    var connectivityRaw: String
    var signalMagnitude: Double?
    var signalUnitRaw: String?
    var lastSeenAt: Date?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?

    init(id: String, assetID: String, name: String, connectivityRaw: String, signalMagnitude: Double?, signalUnitRaw: String?, lastSeenAt: Date?, latitude: Double?, longitude: Double?, altitude: Double?) {
        self.id = id
        self.assetID = assetID
        self.name = name
        self.connectivityRaw = connectivityRaw
        self.signalMagnitude = signalMagnitude
        self.signalUnitRaw = signalUnitRaw
        self.lastSeenAt = lastSeenAt
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

@Model
final class ReadingRecord {
    @Attribute(.unique) var id: String
    var deviceID: String
    var metricKey: String
    var unitRaw: String
    var magnitude: Double
    var recordedAt: Date

    init(id: String, deviceID: String, metricKey: String, unitRaw: String, magnitude: Double, recordedAt: Date) {
        self.id = id
        self.deviceID = deviceID
        self.metricKey = metricKey
        self.unitRaw = unitRaw
        self.magnitude = magnitude
        self.recordedAt = recordedAt
    }
}

@Model
final class EventRecord {
    @Attribute(.unique) var id: String
    var deviceID: String
    var kindKey: String
    var detail: String?
    var occurredAt: Date

    init(id: String, deviceID: String, kindKey: String, detail: String?, occurredAt: Date) {
        self.id = id
        self.deviceID = deviceID
        self.kindKey = kindKey
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

@Model
final class AlertRecord {
    @Attribute(.unique) var id: String
    var deviceID: String
    var ruleID: String
    var metricKey: String
    var severityRaw: String
    var message: String
    var observedMagnitude: Double
    var observedUnitRaw: String
    var raisedAt: Date
    var acknowledgedAt: Date?

    init(id: String, deviceID: String, ruleID: String, metricKey: String, severityRaw: String, message: String, observedMagnitude: Double, observedUnitRaw: String, raisedAt: Date, acknowledgedAt: Date?) {
        self.id = id
        self.deviceID = deviceID
        self.ruleID = ruleID
        self.metricKey = metricKey
        self.severityRaw = severityRaw
        self.message = message
        self.observedMagnitude = observedMagnitude
        self.observedUnitRaw = observedUnitRaw
        self.raisedAt = raisedAt
        self.acknowledgedAt = acknowledgedAt
    }
}

@Model
final class InsightHistoryRecord {
    @Attribute(.unique) var id: String
    var deviceID: String
    var metricKey: String
    var summary: String
    var anomalyExplanation: String
    var recommendation: String
    var severityRaw: String
    var sourceRaw: String
    var confidence: Double
    var createdAt: Date

    init(id: String, deviceID: String, metricKey: String, summary: String, anomalyExplanation: String, recommendation: String, severityRaw: String, sourceRaw: String, confidence: Double, createdAt: Date) {
        self.id = id
        self.deviceID = deviceID
        self.metricKey = metricKey
        self.summary = summary
        self.anomalyExplanation = anomalyExplanation
        self.recommendation = recommendation
        self.severityRaw = severityRaw
        self.sourceRaw = sourceRaw
        self.confidence = confidence
        self.createdAt = createdAt
    }
}
