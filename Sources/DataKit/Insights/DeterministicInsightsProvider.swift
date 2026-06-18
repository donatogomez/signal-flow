import Foundation
import DomainKit

/// A deterministic, offline `InsightsProviding` placeholder.
///
/// It computes a trend from the readings with simple statistics — no AI, no randomness — so the
/// Insights use case has a real, reproducible implementation to build on until the on-device
/// Foundation Models provider (in `IntelligenceKit`) replaces it behind the same port.
public struct DeterministicInsightsProvider: InsightsProviding {
    public init() {}

    public func summarize(
        _ readings: [TelemetryReading],
        for metric: MetricKind,
        over range: TimeRange
    ) async throws -> TelemetryInsight {
        guard readings.count >= 2 else { throw DomainError.insufficientData }

        let sorted = readings.sorted { $0.recordedAt < $1.recordedAt }
        let values = sorted.map(\.value.magnitude)
        let first = values.first ?? 0
        let last = values.last ?? 0
        let delta = last - first
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let standardDeviation = variance.squareRoot()
        let spread = (values.max() ?? 0) - (values.min() ?? 0)

        let trend: TelemetryInsight.Trend
        if spread < 0.001 {
            trend = .stable
        } else if standardDeviation > abs(delta) {
            trend = .volatile
        } else if delta > 0 {
            trend = .rising
        } else if delta < 0 {
            trend = .falling
        } else {
            trend = .stable
        }

        let unit = sorted.first?.value.unit.symbol ?? ""
        let summary = "\(metric.displayName) went from \(format(first)) to \(format(last)) \(unit) "
            + "across \(values.count) readings — \(trend.rawValue)."
        let confidence = min(1.0, Double(values.count) / 50.0)

        return TelemetryInsight(summary: summary, trend: trend, confidence: confidence)
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", value) }
}
