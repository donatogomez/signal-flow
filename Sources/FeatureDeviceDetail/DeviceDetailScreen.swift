import SwiftUI
import Charts
import DomainKit
import DesignSystemKit

/// A single device's detail: current telemetry, trend charts (Swift Charts), active alerts, and a
/// recent-events feed. Vertical, scannable, native — modeled on Apple Stocks/Health detail screens.
public struct DeviceDetailScreen: View {
    @State private var model: DeviceDetailModel

    public init(
        deviceID: DeviceID,
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        events: any EventRepository
    ) {
        _model = State(initialValue: DeviceDetailModel(
            deviceID: deviceID, devices: devices, telemetry: telemetry, alerts: alerts, events: events
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .failed(let message):
                    ContentUnavailableView(loc("Couldn't load the device"), systemImage: "exclamationmark.triangle", description: Text(message))
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .loading:
                    loadingSkeleton
                case .loaded:
                    header
                    currentTelemetry
                    trendCharts
                    activeAlerts
                    recentEvents
                }
            }
            .padding(Spacing.lg)
            .animation(.default, value: model.phase)
        }
        .navigationTitle(model.deviceName.isEmpty ? loc("Device") : model.deviceName)
        .task { await model.observe() }
    }

    /// The device's vitals: status leads as the hero, with connectivity + battery as grouped metadata.
    private var header: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(model.status.symbol, tint: model.status.tint, size: 44)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(model.status.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(model.status.tint)
                HStack(spacing: Spacing.md) {
                    ConnectivityLabel(model.connectivity)
                    BatteryLabel(model.battery)
                }
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var currentTelemetry: some View {
        CardSection(loc("Current telemetry"), systemImage: "gauge.with.dots.needle.bottom.50percent") {
            if model.readings.isEmpty {
                EmptyHint(loc("Waiting for telemetry"), systemImage: "antenna.radiowaves.left.and.right.slash")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.readings) { reading in
                        TelemetryRowView(reading: reading)
                    }
                }
            }
        }
    }

    private var trendCharts: some View {
        ForEach(model.trends, id: \.metric) { series in
            CardSection(loc("\(series.metric.localizedName) trend"), systemImage: series.metric.symbol) {
                TrendChart(series: series)
            }
        }
    }

    private var activeAlerts: some View {
        CardSection(loc("Active alerts"), systemImage: "bell.fill") {
            if model.alerts.isEmpty {
                EmptyHint(loc("No active alerts"), systemImage: "checkmark.seal")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.alerts) { alert in
                        AlertRowView(alert: alert)
                    }
                }
            }
        }
    }

    private var recentEvents: some View {
        CardSection(loc("Recent events"), systemImage: "clock.arrow.circlepath") {
            if model.events.isEmpty {
                EmptyHint(loc("No events yet"), systemImage: "tray")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.events) { event in
                        EventListRow(kind: event.kind, occurredAt: event.occurredAt)
                    }
                }
            }
        }
    }

    /// Neutral grey skeleton shown during the first load — matches the loaded layout's silhouette
    /// (vitals header + a telemetry card + a chart card), consistent with Dashboard and Fleet.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SkeletonCard {
                HStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(.quaternary).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Capsule().fill(.quaternary).frame(width: 120, height: 14)
                        Capsule().fill(.quaternary).frame(width: 170, height: 10)
                    }
                    Spacer()
                }
            }
            SkeletonCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Capsule().fill(.quaternary).frame(width: 150, height: 13)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: Spacing.md) {
                            RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(.quaternary).frame(width: 28, height: 28)
                            Capsule().fill(.quaternary).frame(width: 100, height: 11)
                            Spacer()
                            Capsule().fill(.quaternary).frame(width: 54, height: 11)
                        }
                    }
                }
            }
            SkeletonCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Capsule().fill(.quaternary).frame(width: 120, height: 13)
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(.quaternary).frame(height: 160)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc("Loading device"))
    }
}

/// A card-shaped container for skeleton content (reuses the shared card surface so loading and loaded
/// states share one silhouette).
private struct SkeletonCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .cardSurface()
    }
}

/// A current-telemetry row: a metric-tinted leading badge, the metric name, and a prominent value.
private struct TelemetryRowView: View {
    let reading: ReadingRow

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(reading.metric.symbol, tint: reading.metric.lineTint, size: 28)
            Text(reading.metric.localizedName)
                .font(.subheadline)
            Spacer(minLength: Spacing.sm)
            Text(reading.valueText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A single metric's trend, rendered with Swift Charts. Plain by design — one line in the metric's
/// semantic tint, native axes, no gradients — plus a marker and readout on the latest sample so the
/// chart reads as live data rather than decoration.
private struct TrendChart: View {
    let series: TrendSeries

    private var latest: TrendPoint? { series.points.last }

    private var latestValueText: String? {
        guard let latest else { return nil }
        let value = String(format: "%.1f", latest.value)
        return series.unitSymbol.isEmpty ? value : "\(value) \(series.unitSymbol)"
    }

    var body: some View {
        Chart {
            ForEach(series.points) { point in
                LineMark(
                    x: .value(loc("Time"), point.date),
                    y: .value(series.metric.localizedName, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(series.metric.lineTint)
            }
            if let latest {
                PointMark(
                    x: .value(loc("Time"), latest.date),
                    y: .value(series.metric.localizedName, latest.value)
                )
                .foregroundStyle(series.metric.lineTint)
                .annotation(position: .top, alignment: .trailing) {
                    if let latestValueText {
                        Text(latestValueText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxisLabel(series.unitSymbol)
        .frame(height: 160)
        .accessibilityLabel(Text(loc("\(series.metric.localizedName) trend")))
        .accessibilityValue(Text(latestValueText ?? ""))
    }
}

private struct AlertRowView: View {
    let alert: AlertRow

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SeverityTag(alert.severity)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(alert.message).font(.subheadline)
                Text(alert.raisedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if alert.isAcknowledged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(loc("Acknowledged"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension MetricKind {
    /// Line/badge color for a metric — battery green, temperature orange, humidity blue; others use a
    /// neutral accent so the chart reads as data, not decoration. Shared by the trend line and the
    /// telemetry row's leading badge so a metric reads in one consistent colour.
    var lineTint: Color {
        switch self {
        case .batteryLevel: .green
        case .temperature: .orange
        case .humidity: .blue
        default: .accentColor
        }
    }
}
