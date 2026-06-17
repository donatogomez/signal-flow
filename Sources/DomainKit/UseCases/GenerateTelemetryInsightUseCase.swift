/// Generates a natural-language insight for a device's metric over a time range.
///
/// Guards that there is enough data to say anything meaningful before delegating phrasing to the
/// injected ``InsightsProviding`` service.
public struct GenerateTelemetryInsightUseCase: Sendable {
    private let telemetry: any TelemetryRepository
    private let insights: any InsightsProviding

    public init(telemetry: any TelemetryRepository, insights: any InsightsProviding) {
        self.telemetry = telemetry
        self.insights = insights
    }

    public func callAsFunction(
        deviceID: DeviceID,
        metric: MetricKind,
        range: TimeRange
    ) async throws -> TelemetryInsight {
        let readings = try await telemetry.readings(forDevice: deviceID, metric: metric, in: range)
        guard readings.count >= 2 else { throw DomainError.insufficientData }
        return try await insights.summarize(readings, for: metric, over: range)
    }
}
