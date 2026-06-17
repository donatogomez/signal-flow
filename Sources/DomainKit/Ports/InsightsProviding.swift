/// Produces a ``TelemetryInsight`` from a window of readings.
///
/// Defined with plain domain value types only, so the Foundation Models implementation lives
/// entirely in `IntelligenceKit` and the Domain stays framework-free and testable with a fake.
public protocol InsightsProviding: Sendable {
    func summarize(
        _ readings: [TelemetryReading],
        for metric: MetricKind,
        over range: TimeRange
    ) async throws -> TelemetryInsight
}
