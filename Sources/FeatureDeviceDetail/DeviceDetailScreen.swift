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
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if case .failed(let message) = model.phase {
                    ContentUnavailableView("Couldn't load the device", systemImage: "exclamationmark.triangle", description: Text(message))
                        .frame(maxWidth: .infinity)
                } else {
                    header
                    currentTelemetry
                    trendCharts
                    activeAlerts
                    recentEvents
                }
            }
            .padding(Spacing.lg)
        }
        .navigationTitle(model.deviceName.isEmpty ? "Device" : model.deviceName)
        .task { await model.observe() }
    }

    private var header: some View {
        HStack(spacing: Spacing.lg) {
            StatusBadge(model.status)
            ConnectivityLabel(model.connectivity)
            BatteryLabel(model.battery)
            Spacer()
        }
        .font(.subheadline)
    }

    private var currentTelemetry: some View {
        CardSection("Current telemetry", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            if model.readings.isEmpty {
                EmptyHint("Waiting for telemetry", systemImage: "antenna.radiowaves.left.and.right.slash")
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.readings) { reading in
                        KeyValueRow(reading.metric.displayName, value: reading.valueText, systemImage: reading.metric.symbol)
                    }
                }
            }
        }
    }

    private var trendCharts: some View {
        ForEach(model.trends, id: \.metric) { series in
            CardSection(series.metric.displayName + " trend", systemImage: series.metric.symbol) {
                TrendChart(series: series)
            }
        }
    }

    private var activeAlerts: some View {
        CardSection("Active alerts", systemImage: "bell.fill") {
            if model.alerts.isEmpty {
                EmptyHint("No active alerts", systemImage: "checkmark.seal")
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
        CardSection("Recent events", systemImage: "clock.arrow.circlepath") {
            if model.events.isEmpty {
                EmptyHint("No events yet", systemImage: "tray")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.events) { event in
                        EventListRow(kind: event.kind, occurredAt: event.occurredAt)
                    }
                }
            }
        }
    }
}

/// A single metric's trend, rendered with Swift Charts. Deliberately plain: one line, native axes,
/// the metric's semantic tint — no gradients or decoration.
private struct TrendChart: View {
    let series: TrendSeries

    var body: some View {
        Chart(series.points) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(series.metric.displayName, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(series.metric.lineTint)
        }
        .chartYAxisLabel(series.unitSymbol)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .frame(height: 160)
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
            }
        }
    }
}

private extension MetricKind {
    /// Line color for trend charts — battery uses a fixed green, others use a neutral accent so the
    /// chart reads as data, not decoration.
    var lineTint: Color {
        switch self {
        case .batteryLevel: .green
        case .temperature: .orange
        case .humidity: .blue
        default: .accentColor
        }
    }
}
