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
                subjectCard
                content
            }
            .padding(Spacing.lg)
            .animation(.default, value: model.phase)
        }
        .navigationTitle(loc("Recommendations"))
        .task {
            await model.loadDevices()
            await model.generateInsight()
        }
        .onChange(of: model.selectedDeviceID) { Task { await model.generateInsight() } }
        .onChange(of: model.metric) { Task { await model.generateInsight() } }
    }

    private var subjectCard: some View {
        @Bindable var model = model
        return CardSection(loc("Subject"), systemImage: "scope") {
            VStack(spacing: Spacing.sm) {
                PickerRow(loc("Device"), systemImage: "shippingbox") {
                    Picker(loc("Device"), selection: $model.selectedDeviceID) {
                        ForEach(model.devices) { device in
                            Label(device.name, systemImage: device.assetKind.symbol).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                }
                Divider()
                PickerRow(loc("Metric"), systemImage: "chart.xyaxis.line") {
                    Picker(loc("Metric"), selection: $model.metric) {
                        ForEach(model.metricOptions, id: \.self) { metric in
                            Label(metric.localizedName, systemImage: metric.symbol).tag(metric)
                        }
                    }
                    .labelsHidden()
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.devices.isEmpty {
                ContentUnavailableView(loc("No devices to analyze"), systemImage: "sparkles")
            }
        case .generating:
            insightSkeleton
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

    /// Neutral grey skeleton shown while an insight is generating — matches the insight layout
    /// (priority header + a detail card), consistent with the other screens.
    private var insightSkeleton: some View {
        VStack(spacing: Spacing.xl) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(.quaternary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Capsule().fill(.quaternary).frame(width: 110, height: 14)
                    Capsule().fill(.quaternary).frame(width: 180, height: 10)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .cardSurface()

            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Capsule().fill(.quaternary).frame(width: 130, height: 12)
                        Capsule().fill(.quaternary).frame(height: 10).frame(maxWidth: .infinity)
                        Capsule().fill(.quaternary).frame(width: 220, height: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .cardSurface()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc("Generating on-device insight…"))
    }
}

/// A labelled control row: a leading purpose label and a trailing control, so a `.menu` picker reads
/// "Device → <selection>" rather than a bare button.
private struct PickerRow<Control: View>: View {
    private let title: String
    private let systemImage: String
    private let control: Control

    init(_ title: String, systemImage: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            control
        }
    }
}

/// The rendered insight: priority first (severity, provenance, confidence), then a single grouped
/// detail card. The provenance line fulfills the on-device-AI availability requirement.
private struct InsightCard: View {
    let insight: DeviceInsight

    private var percentText: String { "\(Int(insight.confidence * 100))%" }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            priorityCard
            detailCard
        }
    }

    private var priorityCard: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconBadge(insight.severity.symbol, tint: insight.severity.tint, size: 44)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(insight.severity.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(insight.severity.tint)
                provenanceLabel
                Text(loc("Confidence \(percentText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            InsightSection(title: loc("Summary"), systemImage: "text.alignleft", text: insight.summary)
            InsightSection(title: loc("Potential anomaly"), systemImage: "questionmark.circle", text: insight.anomalyExplanation)
            InsightSection(title: loc("Recommendation"), systemImage: "lightbulb", text: insight.recommendation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
    }

    @ViewBuilder
    private var provenanceLabel: some View {
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

/// One labelled paragraph within the insight's detail card.
private struct InsightSection: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
