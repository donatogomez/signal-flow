import Foundation
import FoundationModels
import os
import DomainKit

/// An `InsightsProviding` implementation backed by Apple's on-device Foundation Models.
///
/// It receives **grounded facts** (computed in Swift via `InsightStatistics`) and asks the model only
/// to *phrase* them with guided generation. It never decides alert status, thresholds or the insight's
/// severity — those are deterministic (`InsightContext.advisorySeverity`) and handed to it as facts.
///
/// Availability and errors degrade gracefully to an injected deterministic `fallback`, and the
/// resulting `DeviceInsight.source` tells the UI which path produced it. Availability is injectable so
/// tests are deterministic on machines without Apple Intelligence.
///
/// Cancellation is not an error to recover from: a cancelled request throws `CancellationError`
/// instead of falling back, so no insight is produced (or recorded) for a screen that has gone away.
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
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: Self.instructions)
            let draft = try await session.respond(
                to: Self.prompt(for: context),
                generating: InsightDraft.self
            ).content

            return DeviceInsight(
                summary: draft.summary,
                anomalyExplanation: draft.anomalyExplanation,
                recommendation: draft.recommendation,
                // Severity and confidence are grounded in Swift, not produced by the model.
                severity: context.advisorySeverity,
                confidence: min(1.0, Double(context.statistics.sampleCount) / 50.0),
                source: .foundationModel
            )
        } catch {
            guard Self.shouldFallBack(after: error) else { throw CancellationError() }
            // Generation failed (including output that doesn't decode into the guided type): the
            // deterministic provider phrases the same facts. Generated content is never logged.
            Self.log.warning("On-device generation failed; using the deterministic fallback: \(String(describing: error), privacy: .private)")
            return try await fallback.insight(for: context)
        }
    }

    /// Whether a failed generation should fall back: any error except cancellation, whether the
    /// framework reports it as `CancellationError` or the task was cancelled while it failed.
    static func shouldFallBack(after error: any Error) -> Bool {
        !(error is CancellationError) && !Task.isCancelled
    }

    private static let log = Logger(subsystem: "com.signalflow.SignalFlow", category: "insights")

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
        Advisory level (already decided, keep your wording consistent with it): \(context.advisorySeverity.rawValue)

        Write a short summary, an anomaly explanation, and an operational recommendation.
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
