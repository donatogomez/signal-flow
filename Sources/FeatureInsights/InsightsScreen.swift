import SwiftUI
import DomainKit
import DesignSystemKit

/// The Insights screen: a calm, fleet-wide **feed of observations** — what the operator should know,
/// surfaced from on-device analysis (or its deterministic fallback). Reads like Apple's Health/Fitness
/// Trends: each card is one observation with its recommendation and a quiet confidence/provenance footer.
/// Not a chat, not a report, not a dashboard.
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
            ForEach(model.items) { InsightFeedCard(item: $0) }
        }
    }

    /// Neutral grey card silhouettes while the feed is generating — hidden from VoiceOver so it doesn't
    /// announce placeholders.
    private var feedSkeleton: some View {
        VStack(spacing: Spacing.lg) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Capsule().fill(.quaternary).frame(width: 140, height: 10)
                    Capsule().fill(.quaternary).frame(height: 16).frame(maxWidth: .infinity)
                    Capsule().fill(.quaternary).frame(width: 220, height: 12)
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

/// One observation in the feed: compact subject metadata, the observation as the dominant text, an
/// optional anomaly line, the recommendation under a quiet label, and a subtle confidence/provenance
/// footer. The whole card is a single VoiceOver element so it reads as one coherent observation.
private struct InsightFeedCard: View {
    let item: InsightFeedItem

    private var confidenceText: String {
        loc("Confidence \(item.confidence.formatted(.percent.precision(.fractionLength(0))))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Subject metadata — quiet, with a shape+colour severity cue.
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.severity.symbol)
                    .foregroundStyle(item.severity.tint)
                    .accessibilityHidden(true)
                Text(verbatim: "\(item.metric.localizedName) · \(item.deviceName)")
                    .textCase(.uppercase)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            // The observation — the largest, dominant text.
            Text(item.observation)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !item.anomaly.isEmpty {
                Text(item.anomaly)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.recommendation.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(loc("Recommendation"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(item.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    /// Provenance + confidence, the quietest line — fulfils the "where the words came from" requirement.
    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: item.source.symbol).accessibilityHidden(true)
            Text(item.source.label)
            Text(verbatim: "·")
            Text(confidenceText).monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
