import Foundation

/// One measurement reported by a device at a point in time.
///
/// Readings are immutable, append-only facts — the system never edits a reading, which is what makes
/// the telemetry history a trustworthy audit trail.
public struct TelemetryReading: Identifiable, Hashable, Sendable, Codable {
    public let id: ReadingID
    public let deviceID: DeviceID
    public let metric: MetricKind
    public let value: MeasuredValue
    public let recordedAt: Date

    public init(
        id: ReadingID = ReadingID(),
        deviceID: DeviceID,
        metric: MetricKind,
        value: MeasuredValue,
        recordedAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.metric = metric
        self.value = value
        self.recordedAt = recordedAt
    }
}
