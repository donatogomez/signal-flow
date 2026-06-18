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

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if case .failed(let message) = model.phase {
                    ContentUnavailableView("Couldn't load the dashboard", systemImage: "exclamationmark.triangle", description: Text(message))
                        .frame(maxWidth: .infinity)
                } else {
                    statTiles
                    statusBreakdown
                    recentEvents
                }
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Dashboard")
        .task { await model.observe() }
    }

    private var statTiles: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            StatTile(title: "Devices", value: "\(model.stats.totalDevices)", systemImage: "shippingbox.fill")
            StatTile(title: "Online", value: "\(model.stats.online)", systemImage: "wifi", tint: .green)
            StatTile(title: "Offline", value: "\(model.stats.offline)", systemImage: "wifi.slash", tint: .secondary)
            StatTile(
                title: "Active alerts",
                value: "\(model.stats.activeAlerts)",
                systemImage: "bell.fill",
                tint: model.stats.activeAlerts > 0 ? .red : .primary
            )
        }
    }

    private var statusBreakdown: some View {
        CardSection("Fleet status", systemImage: "chart.bar.fill") {
            VStack(spacing: Spacing.sm) {
                StatusBreakdownRow(label: DeviceStatus.nominal.label, count: model.stats.nominal, tint: DeviceStatus.nominal.tint)
                StatusBreakdownRow(label: DeviceStatus.warning.label, count: model.stats.warning, tint: DeviceStatus.warning.tint)
                StatusBreakdownRow(label: DeviceStatus.critical.label, count: model.stats.critical, tint: DeviceStatus.critical.tint)
                StatusBreakdownRow(label: DeviceStatus.offline.label, count: model.stats.offline, tint: DeviceStatus.offline.tint)
            }
        }
    }

    private var recentEvents: some View {
        CardSection("Recent events", systemImage: "clock.arrow.circlepath") {
            if model.recentEvents.isEmpty {
                EmptyHint("No events yet", systemImage: "tray")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.recentEvents) { event in
                        EventListRow(kind: event.kind, deviceName: event.deviceName, occurredAt: event.occurredAt)
                    }
                }
            }
        }
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
    }
}

