import Foundation
import FoundationModels
import DomainKit

/// An `InsightsProviding` implementation backed by Apple's on-device Foundation Models.
///
/// It receives **grounded facts** (computed in Swift via `InsightStatistics`) and asks the model only
/// to *phrase* them with guided generation. It never decides alert status or thresholds — those are
/// deterministic and already reflected in the context's counts.
///
/// Availability and errors degrade gracefully to an injected deterministic `fallback`, and the
/// resulting `DeviceInsight.source` tells the UI which path produced it. Availability is injectable so
/// tests are deterministic on machines without Apple Intelligence.
public struct FoundationModelsInsightProvider: InsightsProviding {
    private let fallback: any InsightsProviding
    private let isModelAvailable: @Sendable () -> Bool

    public init(
        fallback: any InsightsProviding,
        isModelAvailable: @escaping @Sendable () -> Bool = { FoundationModelsInsightProvider.systemModelAvailable }
    ) {
        self.fallback = fallback
        self.isModelAvailable = isModelAvailable
    }

    /// Whether the system language model is ready right now.
    public static var systemModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func insight(for context: InsightContext) async throws -> DeviceInsight {
        guard isModelAvailable() else {
            return try await fallback.insight(for: context)
        }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let draft = try await session.respond(
                to: Self.prompt(for: context),
                generating: InsightDraft.self
            ).content

            return DeviceInsight(
                summary: draft.summary,
                anomalyExplanation: draft.anomalyExplanation,
                recommendation: draft.recommendation,
                severity: draft.severity.domain,
                // Confidence is grounded in how much data we have, not produced by the model.
                confidence: min(1.0, Double(context.statistics.sampleCount) / 50.0),
                source: .foundationModel
            )
        } catch {
            // Any model/availability error → graceful deterministic fallback.
            return try await fallback.insight(for: context)
        }
    }

    // MARK: - Grounding

    static var instructions: String {
        """
        You explain IoT sensor telemetry for an operations dashboard.
        Rules:
        - Use ONLY the facts provided. Never invent, estimate, or extrapolate numbers or values.
        - Be concise, concrete, and neutral.
        - Frame any anomaly as a hypothesis ("likely…", "may indicate…"), never as a certainty.
        - Do not give safety verdicts or decide alert status; thresholds are evaluated separately.
        - Write all prose (summary, anomaly explanation, recommendation) in \(outputLanguageName). \
        Keep numbers, units, and the device name exactly as given.
        """
    }

    static func prompt(for context: InsightContext) -> String {
        let s = context.statistics
        return """
        Device: \(context.deviceName) (\(context.assetKind.displayName))
        Metric: \(s.metric.displayName), unit \(s.unit.symbol)
        Latest: \(f(s.latest)); minimum: \(f(s.minimum)); maximum: \(f(s.maximum)); average: \(f(s.average))
        Trend: \(s.trend.label) across \(s.sampleCount) readings
        Active alerts on device: \(context.activeAlertCount)
        Recent events on device: \(context.recentEventCount)

        Write a short summary, an anomaly explanation, an operational recommendation, and an advisory severity.
        """
    }

    /// The user's language, named in English (e.g. "Spanish") so the on-device model reliably honors it.
    /// This is why FM output follows the device language instead of always being English.
    static var outputLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    private static func f(_ value: Double) -> String { String(format: "%.1f", value) }
}
