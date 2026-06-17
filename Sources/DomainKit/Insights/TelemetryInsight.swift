/// The result of summarizing a window of telemetry — a plain-language narrative plus a structured
/// trend and confidence.
///
/// This is a framework-free domain value type. The on-device model integration that produces it
/// (in `IntelligenceKit`) maps its output into this shape, so the Domain never imports
/// `FoundationModels`.
public struct TelemetryInsight: Hashable, Sendable, Codable {
    public enum Trend: String, Codable, Hashable, Sendable, CaseIterable {
        case rising
        case falling
        case stable
        case volatile
    }

    public let summary: String
    public let trend: Trend
    /// Model confidence, clamped to `0...1`.
    public let confidence: Double

    public init(summary: String, trend: Trend, confidence: Double) {
        self.summary = summary
        self.trend = trend
        self.confidence = min(max(confidence, 0), 1)
    }
}
