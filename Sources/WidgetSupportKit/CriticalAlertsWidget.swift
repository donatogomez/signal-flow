import WidgetKit
import SwiftUI
import DomainKit
import DesignSystemKit
import SnapshotKit

/// **Critical Alerts** widget — the most pressing active alerts with their device and severity. Reads
/// persisted state only; tapping deep-links into the in-app Alerts screen.
public struct CriticalAlertsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SignalFlowWidgetConfiguration.self, provider: CriticalAlertsProvider()) { entry in
            CriticalAlertsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Critical Alerts")
        .description("The top active alerts across your fleet.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    static let kind = "CriticalAlertsWidget"
}

/// How many rows each family shows. Kept here so the provider trims the timeline to what fits.
enum CriticalAlertsLayout {
    static func rows(for family: WidgetFamily) -> Int {
        family == .systemSmall ? 3 : 4
    }
}

struct CriticalAlertsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CriticalAlertsEntry { .placeholder }

    func snapshot(for configuration: SignalFlowWidgetConfiguration, in context: Context) async -> CriticalAlertsEntry {
        let now = Date()
        let data = await WidgetDataLoader.load(now: now)
        return CriticalAlertsEntry(date: now, alerts: data.alerts)
    }

    func timeline(for configuration: SignalFlowWidgetConfiguration, in context: Context) async -> Timeline<CriticalAlertsEntry> {
        let now = Date()
        let data = await WidgetDataLoader.load(now: now)
        // Keep enough for the largest supported family; the view trims per family.
        return WidgetTimeline.alerts(data, now: now, limit: CriticalAlertsLayout.rows(for: .systemMedium))
    }
}

// MARK: - View

struct CriticalAlertsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CriticalAlertsEntry

    private var visible: [WidgetAlert] {
        Array(entry.alerts.prefix(CriticalAlertsLayout.rows(for: family)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if visible.isEmpty {
                emptyState
            } else {
                ForEach(visible) { AlertRowView(alert: $0, compact: family == .systemSmall) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(DeepLinkRoute.alerts.url)
    }

    private var header: some View {
        HStack {
            Label("Critical Alerts", systemImage: "bell.badge.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !entry.alerts.isEmpty {
                Text("\(entry.alerts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(entry.alerts.count) active alerts")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(DeviceStatus.nominal.tint)
            Text("No active alerts")
                .font(.subheadline.weight(.medium))
            Text("The fleet looks healthy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// One alert line: a severity swatch, the device name, and (when room allows) the message.
private struct AlertRowView: View {
    let alert: WidgetAlert
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle()
                .fill(alert.severity.tint)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.deviceName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !compact {
                    Text(alert.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.severity.label) on \(alert.deviceName). \(alert.message)")
    }
}

#Preview("Alerts · medium", as: .systemMedium) {
    CriticalAlertsWidget()
} timeline: {
    CriticalAlertsEntry(date: .now, alerts: [])
}
