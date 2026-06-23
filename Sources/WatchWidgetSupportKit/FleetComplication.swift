#if os(watchOS)
import WidgetKit
import SwiftUI
import SnapshotKit
import WatchConnectivityKit

/// **Fleet Health** complication / Smart Stack widget for watchOS. Reads the snapshot the iPhone synced
/// to the watch (``WatchConnectivityKit/WatchSyncSnapshotStore``) — never the data engine — and renders a
/// concise, severity-first health glance across the accessory families. Tapping it opens the watch app.
public struct FleetComplication: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchFleetProvider()) { entry in
            FleetComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(DeepLinkRoute.fleet.url)
        }
        .configurationDisplayName(loc("Fleet Health"))
        .description(loc("Critical and warning counts at a glance."))
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular, .accessoryCorner])
    }

    public static let kind = "FleetComplication"
}

/// Emits a single entry per refresh window from the locally-synced snapshot store.
struct WatchFleetProvider: TimelineProvider {
    private let store: WatchSyncSnapshotStore

    init(store: WatchSyncSnapshotStore = WatchSyncSnapshotStore()) {
        self.store = store
    }

    func placeholder(in context: Context) -> WatchComplicationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(WatchComplicationModel.nextReload(after: entry.date))))
    }

    private func currentEntry() -> WatchComplicationEntry {
        WatchComplicationModel.entry(from: store.load() ?? .empty, now: Date())
    }
}

// MARK: - View

struct FleetComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchComplicationEntry

    private var model: WatchComplicationViewModel { WatchComplicationViewModel(entry) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // accessoryInline — one tinted line on the watch face.
    private var inline: some View {
        Label(model.statusLine, systemImage: symbol)
    }

    // accessoryCircular — the worst count, with a small severity glyph, over the standard backing.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(model.compactCount)
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.6)
            }
        }
        .widgetAccessibilityLabel(model.statusLine)
    }

    // accessoryCorner — a glyph in the corner with a curved status label.
    private var corner: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(tint)
            .widgetLabel(model.statusLine)
    }

    // accessoryRectangular — headline + top critical device + freshness footnote.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(model.statusLine)
                    .font(.headline)
                    .lineLimit(2)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            if let device = model.topAlertDeviceName {
                Text(device)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            footnote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footnote: some View {
        if let reference = model.referenceDate {
            if model.isStale {
                Text("\(model.staleText) · \(reference, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text("\(loc("Updated")) \(reference, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        switch model.tone {
        case .critical: .red
        case .warning: .orange
        case .nominal: .green
        case .neutral: .secondary
        }
    }

    private var symbol: String {
        switch model.tone {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .nominal: "checkmark.circle.fill"
        case .neutral: "antenna.radiowaves.left.and.right.slash"
        }
    }
}

private extension View {
    /// Small shim so the circular layout can carry a spoken label without an extra modifier import dance.
    func widgetAccessibilityLabel(_ label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(Text(label))
    }
}

// MARK: - Previews

#Preview("Rectangular", as: .accessoryRectangular) {
    FleetComplication()
} timeline: {
    WatchComplicationEntry.placeholder
    WatchComplicationEntry(date: .now, online: 10, warning: 0, critical: 0, offline: 0,
                           topAlert: nil, referenceDate: .now, freshness: .fresh)
}

#Preview("Circular", as: .accessoryCircular) {
    FleetComplication()
} timeline: {
    WatchComplicationEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    FleetComplication()
} timeline: {
    WatchComplicationEntry.placeholder
}
#endif
