import SwiftUI
import DomainKit
import DesignSystemKit

/// The Insights screen: a calm, fleet-wide digest — "Observaciones" (what's trending) and
/// "Recomendaciones" (what to do). Reads like Apple's Health/Fitness Trends: each observation is a short
/// derived headline with a change figure and a sparkline, not a wall of AI prose. Not a chat, not a report.
public struct InsightsScreen: View {
    @State private var model: InsightsModel

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        events: any EventRepository,
        insights: any InsightsProviding
    ) {
        _model = State(initialValue: InsightsModel(
            assets: assets, devices: devices, telemetry: telemetry, alerts: alerts, events: events, insights: insights
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                content
            }
            .padding(Spacing.lg)
            .animation(.default, value: model.phase)
        }
        .background(Color.signalFlowGroupedBackground.ignoresSafeArea())
        .navigationTitle(loc("Insights"))
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            feedSkeleton
        case .failed(let message):
            ContentUnavailableView(loc("Couldn't generate an insight"), systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity, minHeight: 320)
        case .empty:
            ContentUnavailableView(
                loc("No observations yet"),
                systemImage: "sparkles",
                description: Text(loc("Insights about your fleet will appear here."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        case .ready:
            sectionHeader(loc("Observations"))
            ForEach(model.items) { ObservationCard(item: $0) }

            if !model.recommendations.isEmpty {
                sectionHeader(loc("Recommendations"))
                    .padding(.top, Spacing.sm)
                ForEach(model.recommendations) { RecommendationCard(item: $0) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Neutral grey card silhouettes while the feed is generating — hidden from VoiceOver.
    private var feedSkeleton: some View {
        VStack(spacing: Spacing.lg) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Capsule().fill(.quaternary).frame(width: 150, height: 10)
                    Capsule().fill(.quaternary).frame(width: 200, height: 18)
                    RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(.quaternary).frame(height: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.cardPadding)
                .cardSurface()
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// One observation: subject metadata, a short derived headline, the change figure, a context line, and a
/// sparkline — then a quiet provenance/confidence footer. One combined VoiceOver element.
private struct ObservationCard: View {
    let item: InsightFeedItem

    private var confidenceText: String {
        loc("Confidence \(item.confidence.formatted(.percent.precision(.fractionLength(0))))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.severity.symbol)
                    .foregroundStyle(item.severity.tint)
                    .accessibilityHidden(true)
                Text(verbatim: "\(item.metric.localizedName) · \(item.deviceName)")
                    .textCase(.uppercase)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(item.headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let changeText = item.changeText {
                Text(changeText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(item.severity.tint)
                    .monospacedDigit()
            }

            Text(item.context)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if item.trend.count >= 2 {
                Sparkline(points: item.trend, tint: item.severity.tint)
                    .padding(.top, Spacing.xs)
            }

            HStack(spacing: Spacing.xs) {
                Image(systemName: item.source.symbol).accessibilityHidden(true)
                Text(item.source.label)
                Text(verbatim: "·")
                Text(confidenceText).monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// One recommendation: a leading check, the action, and its subject. One combined VoiceOver element.
private struct RecommendationCard: View {
    let item: InsightFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconBadge("checkmark.circle.fill", tint: .green)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.recommendation)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(item.metric.localizedName) · \(item.deviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
