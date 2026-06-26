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
                    if model.readings.isEmpty {
                        waitingForTelemetry
                    } else {
                        primaryMetricCard
                        vitalsCard
                    }
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

    /// The screen's answer to "what is happening?": the most important metric as a large value with its
    /// change, and its single trend chart — one calm card, no competing charts.
    @ViewBuilder
    private var primaryMetricCard: some View {
        if let reading = primaryReading {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                MetricHeroValue(
                    title: reading.metric.localizedName,
                    value: reading.valueText,
                    caption: primaryDelta?.text,
                    captionSymbol: primaryDelta?.symbol
                )
                if let trend = primaryTrend, !trend.isEmpty {
                    TrendChart(series: trend)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .cardSurface()
        }
    }

    /// Supporting vitals: the device's other current readings as plain rows (the primary metric is the
    /// hero above, so it's not repeated here). Hidden when there's nothing else to show.
    @ViewBuilder
    private var vitalsCard: some View {
        let others = otherReadings
        if !others.isEmpty {
            CardSection(loc("Current telemetry"), systemImage: "gauge.with.dots.needle.bottom.50percent") {
                VStack(spacing: Spacing.md) {
                    ForEach(others) { TelemetryRowView(reading: $0) }
                }
            }
        }
    }

    private var waitingForTelemetry: some View {
        EmptyHint(loc("Waiting for telemetry"), systemImage: "antenna.radiowaves.left.and.right.slash")
            .frame(maxWidth: .infinity)
            .padding(Spacing.cardPadding)
            .cardSurface()
    }

    // MARK: Primary-metric selection (view-layer presentation; no model changes)

    /// Priority order for the hero metric — environmental signals first, infrastructure last.
    private static let metricPriority: [MetricKind] = [.temperature, .humidity, .carbonDioxide, .batteryLevel, .signalStrength]

    private var primaryReading: ReadingRow? {
        for metric in Self.metricPriority {
            if let row = model.readings.first(where: { $0.metric == metric }) { return row }
        }
        return model.readings.first
    }

    private var primaryTrend: TrendSeries? {
        guard let primaryReading else { return nil }
        return model.trends.first { $0.metric == primaryReading.metric }
    }

    private var otherReadings: [ReadingRow] {
        model.readings.filter { $0.id != primaryReading?.id }
    }

    /// The hero's change caption — signed value + a direction glyph over the charted window. Neutral
    /// (`.secondary`) so it states the change without implying good/bad. `nil` when there's no trend.
    private var primaryDelta: (text: String, symbol: String)? {
        guard let series = primaryTrend, series.points.count >= 2,
              let first = series.points.first, let last = series.points.last else { return nil }
        let diff = last.value - first.value
        let minutes = max(Int((last.date.timeIntervalSince(first.date) / 60).rounded()), 0)
        let magnitude = abs(diff).formatted(.number.precision(.fractionLength(0...1)))
        let unit = series.unitSymbol.isEmpty ? "" : " \(series.unitSymbol)"
        let sign = diff > 0 ? "+" : (diff < 0 ? "−" : "")
        let valueText = "\(sign)\(magnitude)\(unit)"
        let symbol = diff > 0 ? "arrow.up.right" : (diff < 0 ? "arrow.down.right" : "arrow.right")
        return (loc("\(valueText) in \(minutes) min"), symbol)
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
                    ForEach(model.events.prefix(4)) { event in
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
        let value = latest.value.formatted(.number.precision(.fractionLength(0...1)))
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
                // A marker on the latest sample so the line reads as live data; the value itself is the
                // hero above, so it isn't repeated as an annotation here.
                PointMark(
                    x: .value(loc("Time"), latest.date),
                    y: .value(series.metric.localizedName, latest.value)
                )
                .foregroundStyle(series.metric.lineTint)
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
