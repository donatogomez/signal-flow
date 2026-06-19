import WidgetKit
import SwiftUI
import DomainKit
import DesignSystemKit

/// **Fleet Status** widget — at-a-glance counts of online / warning / critical devices, plus when the
/// data was last refreshed. Reads persisted state only (see ``WidgetSnapshotReader``).
public struct FleetStatusWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SignalFlowWidgetConfiguration.self, provider: FleetStatusProvider()) { entry in
            FleetStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fleet Status")
        .description("Online, warning, and critical devices across your fleet.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    static let kind = "FleetStatusWidget"
}

/// Loads the persisted snapshot and emits a single entry per refresh window.
struct FleetStatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FleetStatusEntry { .placeholder }

    func snapshot(for configuration: SignalFlowWidgetConfiguration, in context: Context) async -> FleetStatusEntry {
        let now = Date()
        let data = await WidgetDataLoader.load(now: now)
        return FleetStatusEntry(date: now, fleet: data.fleet)
    }

    func timeline(for configuration: SignalFlowWidgetConfiguration, in context: Context) async -> Timeline<FleetStatusEntry> {
        let now = Date()
        let data = await WidgetDataLoader.load(now: now)
        return WidgetTimeline.fleet(data, now: now)
    }
}

// MARK: - View

struct FleetStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FleetStatusEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
        .widgetURL(WidgetRoute.dashboard.url)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            Spacer(minLength: 0)
            Text("\(entry.fleet.online)")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(DeviceStatus.nominal.tint)
                .contentTransition(.numericText())
            Text("online")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                count(.warning, entry.fleet.warning)
                count(.critical, entry.fleet.critical)
            }
            updatedFootnote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            HStack(spacing: Spacing.md) {
                tile(.nominal, entry.fleet.online, "Online")
                tile(.warning, entry.fleet.warning, "Warning")
                tile(.critical, entry.fleet.critical, "Critical")
            }
            updatedFootnote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        Label("Fleet Status", systemImage: "antenna.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func tile(_ status: DeviceStatus, _ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .imageScale(.medium)
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(title.lowercased()) devices")
    }

    private func count(_ status: DeviceStatus, _ value: Int) -> some View {
        Label("\(value)", systemImage: status.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.tint)
            .accessibilityLabel("\(value) \(status.label.lowercased())")
    }

    @ViewBuilder
    private var updatedFootnote: some View {
        if let updated = entry.fleet.lastUpdated {
            Text("Updated \(updated, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text("No data yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview("Fleet · small", as: .systemSmall) {
    FleetStatusWidget()
} timeline: {
    FleetStatusEntry(date: .now, fleet: FleetSummary(online: 8, warning: 1, critical: 1, offline: 0, lastUpdated: .now))
}

#Preview("Fleet · medium", as: .systemMedium) {
    FleetStatusWidget()
} timeline: {
    FleetStatusEntry(date: .now, fleet: FleetSummary(online: 6, warning: 2, critical: 2, offline: 0, lastUpdated: .now))
}
