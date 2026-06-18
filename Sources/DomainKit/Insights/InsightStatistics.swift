import Foundation

/// Grounded statistics for one metric over a window — min/max/average/latest plus a derived trend.
///
/// This is the heart of the "facts in Swift, words in the model" strategy: every number an insight is
/// built from is computed here, deterministically, and handed to the insight provider. A model
/// (when used) only *phrases* these facts; it never produces them.
public struct InsightStatistics: Sendable, Hashable, Codable {
    public let metric: MetricKind
    public let unit: MeasurementUnit
    public let latest: Double
    public let minimum: Double
    public let maximum: Double
    public let average: Double
    public let trend: TrendDirection
    public let sampleCount: Int

    public init(
        metric: MetricKind,
        unit: MeasurementUnit,
        latest: Double,
        minimum: Double,
        maximum: Double,
        average: Double,
        trend: TrendDirection,
        sampleCount: Int
    ) {
        self.metric = metric
        self.unit = unit
        self.latest = latest
        self.minimum = minimum
        self.maximum = maximum
        self.average = average
        self.trend = trend
        self.sampleCount = sampleCount
    }

    /// Computes statistics from a device's readings for `metric`. Returns `nil` when there are fewer
    /// than two readings — not enough to describe a trend.
    public static func make(from readings: [TelemetryReading], metric: MetricKind) -> InsightStatistics? {
        let sorted = readings.filter { $0.metric == metric }.sorted { $0.recordedAt < $1.recordedAt }
        guard sorted.count >= 2, let unit = sorted.first?.value.unit else { return nil }

        let values = sorted.map(\.value.magnitude)
        let first = values.first ?? 0
        let last = values.last ?? 0
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let average = values.reduce(0, +) / Double(values.count)
        let delta = last - first
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
        let standardDeviation = variance.squareRoot()
        let spread = maximum - minimum

        let trend: TrendDirection
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

        return InsightStatistics(
            metric: metric, unit: unit, latest: last, minimum: minimum, maximum: maximum,
            average: average, trend: trend, sampleCount: values.count
        )
    }
}
