import Foundation
import DomainKit

/// A deterministic, offline `InsightsProviding` implementation — and the fallback used whenever the
/// Foundation Models provider is unavailable.
///
/// It phrases the grounded `InsightContext` with simple templates: no AI, no randomness, fully
/// reproducible. The templates are **localized** against DataKit's string catalog (`Bundle.module`), so
/// the fallback insight follows the device language. The grounded facts it speaks (metric name, trend)
/// are localized here too, since this concrete provider can't reach the presentation layer.
public struct DeterministicInsightsProvider: InsightsProviding {
    public init() {}

    public func insight(for context: InsightContext) async throws -> DeviceInsight {
        let stats = context.statistics
        let unit = stats.unit.symbol
        let metricName = metricName(stats.metric)

        let summary = String(
            localized: "\(metricName) on \(context.deviceName) is \(fmt(stats.latest)) \(unit) now, averaging \(fmt(stats.average)) \(unit) across \(stats.sampleCount) readings (range \(fmt(stats.minimum))–\(fmt(stats.maximum)) \(unit), \(trendWord(stats.trend))).",
            bundle: .module
        )

        let anomalyExplanation: String
        if context.activeAlertCount > 0 {
            let alertsPhrase = String(localized: "\(context.activeAlertCount) active alerts open on this device.", bundle: .module)
            let relatedPhrase = String(localized: "The recent \(metricName.lowercased()) movement may be related.", bundle: .module)
            anomalyExplanation = "\(alertsPhrase) \(relatedPhrase)"
        } else if stats.trend == .volatile {
            anomalyExplanation = String(localized: "Readings have been volatile across the window, which can indicate an unstable environment or an intermittent sensor.", bundle: .module)
        } else {
            anomalyExplanation = String(localized: "No unusual pattern detected in the available window.", bundle: .module)
        }

        let recommendation: String
        if context.activeAlertCount > 0 {
            recommendation = String(localized: "Review the active alerts for \(context.deviceName) and confirm conditions on site.", bundle: .module)
        } else if stats.trend == .rising {
            recommendation = String(localized: "Keep monitoring; \(metricName.lowercased()) is trending up.", bundle: .module)
        } else if stats.trend == .falling {
            recommendation = String(localized: "Keep monitoring; \(metricName.lowercased()) is trending down.", bundle: .module)
        } else {
            recommendation = String(localized: "No action needed; continue routine monitoring.", bundle: .module)
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

    /// Localized metric name (this layer can't reach DesignSystemKit's `localizedName`).
    private func metricName(_ metric: MetricKind) -> String {
        switch metric {
        case .temperature: String(localized: "Temperature", bundle: .module)
        case .humidity: String(localized: "Humidity", bundle: .module)
        case .carbonDioxide: String(localized: "Carbon dioxide", bundle: .module)
        case .batteryLevel: String(localized: "Battery level", bundle: .module)
        case .signalStrength: String(localized: "Signal strength", bundle: .module)
        case .custom(let key): key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Localized trend word (the domain's `TrendDirection.label` is language-neutral English).
    private func trendWord(_ trend: TrendDirection) -> String {
        switch trend {
        case .rising: String(localized: "rising", bundle: .module)
        case .falling: String(localized: "falling", bundle: .module)
        case .stable: String(localized: "holding steady", bundle: .module)
        case .volatile: String(localized: "volatile", bundle: .module)
        }
    }
}
