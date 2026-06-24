import SwiftUI
import DomainKit
import DesignSystemKit

/// The Insights screen: pick a device and metric, then see an on-device AI insight (or a clearly
/// labeled deterministic fallback) — summary, anomaly hypothesis, recommendation, and advisory
/// severity. Native, calm, and honest about where the words came from.
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
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                CardSection(loc("Subject"), systemImage: "scope") {
                    VStack(spacing: Spacing.md) {
                        Picker(loc("Device"), selection: $model.selectedDeviceID) {
                            ForEach(model.devices) { device in
                                Label(device.name, systemImage: device.assetKind.symbol).tag(Optional(device.id))
                            }
                        }
                        Picker(loc("Metric"), selection: $model.metric) {
                            ForEach(model.metricOptions, id: \.self) { metric in
                                Label(metric.localizedName, systemImage: metric.symbol).tag(metric)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }
                content
            }
            .padding(Spacing.lg)
        }
        .navigationTitle(loc("Insights"))
        .task {
            await model.loadDevices()
            await model.generateInsight()
        }
        .onChange(of: model.selectedDeviceID) { Task { await model.generateInsight() } }
        .onChange(of: model.metric) { Task { await model.generateInsight() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .generating:
            CardSection(loc("Insight"), systemImage: "sparkles") {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text(loc("Generating on-device insight…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .insufficientData:
            ContentUnavailableView(
                loc("Not enough data"),
                systemImage: "chart.line.downtrend.xyaxis",
                description: Text(loc("This device hasn't reported enough \(model.metric.localizedName.lowercased()) readings yet."))
            )
        case .failed(let message):
            ContentUnavailableView(loc("Couldn't generate an insight"), systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            if let insight = model.insight {
                InsightCard(insight: insight)
            }
        }
    }
}

/// The rendered insight, including the provenance banner that fulfills the availability requirement.
private struct InsightCard: View {
    let insight: DeviceInsight

    /// Pre-formatted so the localized key is "Confidence %@" — the "%" stays in the value, not the key.
    private var percentText: String { "\(Int(insight.confidence * 100))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            provenanceBanner

            CardSection(loc("Summary"), systemImage: "text.alignleft") {
                Text(insight.summary)
            }
            CardSection(loc("Potential anomaly"), systemImage: "questionmark.circle") {
                Text(insight.anomalyExplanation)
            }
            CardSection(loc("Recommendation"), systemImage: "lightbulb") {
                Text(insight.recommendation)
            }

            HStack {
                Label(insight.severity.label, systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundStyle(insight.severity.tint)
                Spacer()
                Text(loc("Confidence \(percentText)"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var provenanceBanner: some View {
        switch insight.source {
        case .foundationModel:
            Label(loc("Generated on-device by Apple Intelligence. Telemetry never leaves your device."),
                  systemImage: InsightSource.foundationModel.symbol)
                .font(.caption)
                .foregroundStyle(.blue)
        case .deterministic:
            Label(loc("On-device AI is unavailable — showing a deterministic insight instead."),
                  systemImage: InsightSource.deterministic.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
