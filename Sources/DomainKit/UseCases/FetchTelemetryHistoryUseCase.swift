/// Loads a device's history for one metric over a validated time range, ordered oldest-first for
/// charting.
public struct FetchTelemetryHistoryUseCase: Sendable {
    private let telemetry: any TelemetryRepository

    public init(telemetry: any TelemetryRepository) {
        self.telemetry = telemetry
    }

    public func callAsFunction(
        deviceID: DeviceID,
        metric: MetricKind,
        range: TimeRange
    ) async throws -> [TelemetryReading] {
        try await telemetry
            .readings(forDevice: deviceID, metric: metric, in: range)
            .sorted { $0.recordedAt < $1.recordedAt }
    }
}
