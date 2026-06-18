/// How noteworthy an insight is — **advisory only**. This is *not* the device's safety status:
/// `DeviceStatus` and `Alert` are decided deterministically by ``DeviceHealthPolicy`` and
/// ``AlertRule``. `InsightSeverity` is a soft hint for ranking insights, nothing more.
public enum InsightSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    case nominal
    case watch
    case concern
}

/// Where an insight came from — surfaced in the UI so the user always knows whether on-device AI was
/// used or a deterministic fallback was shown.
public enum InsightSource: String, Codable, Hashable, Sendable {
    /// Generated on-device by an Apple Foundation model.
    case foundationModel
    /// Computed locally by the deterministic provider (model unavailable or not used).
    case deterministic
}

/// A natural-language insight about a device's recent telemetry: a summary, an anomaly hypothesis, a
/// recommendation, plus an advisory severity and confidence. A framework-free domain value type — the
/// Foundation Models implementation maps its output into this shape, so the Domain never imports
/// `FoundationModels`.
public struct DeviceInsight: Sendable, Hashable, Codable {
    public let summary: String
    public let anomalyExplanation: String
    public let recommendation: String
    public let severity: InsightSeverity
    /// Confidence in `0...1`, derived from the amount of grounded data — not produced by the model.
    public let confidence: Double
    public let source: InsightSource

    public init(
        summary: String,
        anomalyExplanation: String,
        recommendation: String,
        severity: InsightSeverity,
        confidence: Double,
        source: InsightSource
    ) {
        self.summary = summary
        self.anomalyExplanation = anomalyExplanation
        self.recommendation = recommendation
        self.severity = severity
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
    }
}
