import SwiftUI
import DomainKit
import DesignSystemKit

/// The monitoring home: headline figures, a fleet status breakdown, and a recent-events feed.
/// Information-dense and calm — modeled on Apple's Weather/Home summary surfaces.
public struct DashboardScreen: View {
    @State private var model: DashboardModel

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        events: any EventRepository
    ) {
        _model = State(initialValue: DashboardModel(assets: assets, devices: devices, alerts: alerts, events: events))
    }

    /// A stable 2-up grid: four headline tiles read as a balanced 2×2 block rather than reflowing
    /// between two and three columns at different widths.
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .failed(let message):
                    errorState(message)
                case .loading:
                    content(placeholder: true)
                        .redacted(reason: .placeholder)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(loc("Loading dashboard"))
                case .loaded:
                    content(placeholder: false)
                }
            }
            .padding(Spacing.lg)
            .animation(.default, value: model.phase)
        }
        .navigationTitle(loc("Dashboard"))
        .task { await model.observe() }
    }

    @ViewBuilder
    private func content(placeholder: Bool) -> some View {
        statTiles
        statusBreakdown
        recentEvents(placeholder: placeholder)
    }

    private var statTiles: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            StatTile(title: loc("Devices"), value: "\(model.stats.totalDevices)", systemImage: "shippingbox.fill")
            StatTile(title: loc("Online"), value: "\(model.stats.online)", systemImage: "wifi", tint: .green)
            StatTile(title: loc("Offline"), value: "\(model.stats.offline)", systemImage: "wifi.slash", tint: .secondary)
            StatTile(
                title: loc("Active alerts"),
                value: "\(model.stats.activeAlerts)",
                systemImage: "bell.fill",
                tint: model.stats.activeAlerts > 0 ? .red : .primary
            )
        }
    }

    private var statusBreakdown: some View {
        CardSection(loc("Fleet status"), systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FleetProportionBar(segments: [
                    (model.stats.nominal, DeviceStatus.nominal.tint),
                    (model.stats.warning, DeviceStatus.warning.tint),
                    (model.stats.critical, DeviceStatus.critical.tint),
                    (model.stats.offline, DeviceStatus.offline.tint)
                ])
                VStack(spacing: Spacing.sm) {
                    StatusBreakdownRow(label: DeviceStatus.nominal.label, count: model.stats.nominal, tint: DeviceStatus.nominal.tint)
                    StatusBreakdownRow(label: DeviceStatus.warning.label, count: model.stats.warning, tint: DeviceStatus.warning.tint)
                    StatusBreakdownRow(label: DeviceStatus.critical.label, count: model.stats.critical, tint: DeviceStatus.critical.tint)
                    StatusBreakdownRow(label: DeviceStatus.offline.label, count: model.stats.offline, tint: DeviceStatus.offline.tint)
                }
            }
        }
    }

    private func recentEvents(placeholder: Bool) -> some View {
        CardSection(loc("Recent events"), systemImage: "clock.arrow.circlepath") {
            if placeholder {
                // Skeleton rows; redaction greys them while the first load is in flight.
                VStack(spacing: Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        EventListRow(kind: .connected, occurredAt: .now)
                    }
                }
            } else if model.recentEvents.isEmpty {
                EmptyHint(loc("No events yet"), systemImage: "tray")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.recentEvents) { event in
                        EventListRow(kind: event.kind, deviceName: event.deviceName, occurredAt: event.occurredAt)
                    }
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView(
            loc("Couldn't load the dashboard"),
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// A thin segmented capsule showing the fleet's status mix at a glance — the Fleet-status card's
/// visual anchor. Purely decorative (the rows below convey the same counts textually), so it's hidden
/// from VoiceOver.
private struct FleetProportionBar: View {
    let segments: [(count: Int, tint: Color)]

    private var total: CGFloat { max(CGFloat(segments.reduce(0) { $0 + $1.count }), 1) }

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            if segment.count > 0 {
                                segment.tint
                                    .frame(width: proxy.size.width * CGFloat(segment.count) / total)
                            }
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

private struct StatusBreakdownRow: View {
    let label: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle().fill(tint).frame(width: 10, height: 10)
            Text(label)
            Spacer()
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(count)"))
    }
}
