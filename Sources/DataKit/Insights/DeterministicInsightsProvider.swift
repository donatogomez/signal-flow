import Foundation
import DomainKit

/// A deterministic, offline `InsightsProviding` implementation — and the fallback used whenever the
/// Foundation Models provider is unavailable.
///
/// It phrases the grounded `InsightContext` with simple templates: no AI, no randomness, fully
/// reproducible. It is the safety net that guarantees the Insights feature always has something
/// truthful to show.
public struct DeterministicInsightsProvider: InsightsProviding {
    public init() {}

    public func insight(for context: InsightContext) async throws -> DeviceInsight {
        let stats = context.statistics
        let unit = stats.unit.symbol
        let metricName = stats.metric.displayName

        let summary = "\(metricName) on \(context.deviceName) is \(fmt(stats.latest)) \(unit) now, "
            + "averaging \(fmt(stats.average)) \(unit) across \(stats.sampleCount) readings "
            + "(range \(fmt(stats.minimum))–\(fmt(stats.maximum)) \(unit), \(stats.trend.label))."

        let anomalyExplanation: String
        if context.activeAlertCount > 0 {
            let plural = context.activeAlertCount == 1 ? "alert is" : "alerts are"
            anomalyExplanation = "\(context.activeAlertCount) active \(plural) open on this device; "
                + "the recent \(metricName.lowercased()) movement may be related."
        } else if stats.trend == .volatile {
            anomalyExplanation = "Readings have been volatile across the window, which can indicate an "
                + "unstable environment or an intermittent sensor."
        } else {
            anomalyExplanation = "No unusual pattern detected in the available window."
        }

        let recommendation: String
        if context.activeAlertCount > 0 {
            recommendation = "Review the active alerts for \(context.deviceName) and confirm conditions on site."
        } else if stats.trend == .rising || stats.trend == .falling {
            recommendation = "Keep monitoring; \(metricName.lowercased()) is trending \(stats.trend == .rising ? "up" : "down")."
        } else {
            recommendation = "No action needed; continue routine monitoring."
        }

        let severity: InsightSeverity = context.activeAlertCount > 0
            ? .concern
            : (stats.trend == .volatile ? .watch : .nominal)

        return DeviceInsight(
            summary: summary,
            anomalyExplanation: anomalyExplanation,
            recommendation: recommendation,
            severity: severity,
            confidence: min(1.0, Double(stats.sampleCount) / 50.0),
            source: .deterministic
        )
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
}
