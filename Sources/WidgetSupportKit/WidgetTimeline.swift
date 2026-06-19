import Foundation
import WidgetKit
import SnapshotKit

/// Timeline entry for the Fleet Status widget.
public struct FleetStatusEntry: TimelineEntry, Sendable, Equatable {
    public let date: Date
    public let fleet: FleetSummary

    public init(date: Date, fleet: FleetSummary) {
        self.date = date
        self.fleet = fleet
    }

    public static let placeholder = FleetStatusEntry(date: .now, fleet: WidgetData.placeholder.fleet)
}

/// Timeline entry for the Critical Alerts widget.
public struct CriticalAlertsEntry: TimelineEntry, Sendable, Equatable {
    public let date: Date
    public let alerts: [WidgetAlert]

    public init(date: Date, alerts: [WidgetAlert]) {
        self.date = date
        self.alerts = alerts
    }

    public static let placeholder = CriticalAlertsEntry(date: .now, alerts: [])
}

/// Deterministic refresh policy shared by both widgets.
///
/// Widgets render persisted state, which the foreground app refreshes far more often than a widget
/// ever could. So we ask WidgetKit for **one** entry now and to come back after a fixed interval —
/// no per-minute polling (the system would throttle that anyway, and it would waste the daily refresh
/// budget). The single knob lives here so both widgets and their tests agree.
public enum WidgetTimeline {
    /// How long an entry stays valid before WidgetKit should ask for a fresh one.
    public static let refreshInterval: TimeInterval = 15 * 60

    /// The next time WidgetKit should request a reload after producing an entry at `date`.
    public static func nextReload(after date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }

    /// A single-entry Fleet Status timeline with an `.after` reload policy.
    public static func fleet(_ data: WidgetData, now: Date) -> Timeline<FleetStatusEntry> {
        Timeline(entries: [FleetStatusEntry(date: now, fleet: data.fleet)], policy: .after(nextReload(after: now)))
    }

    /// A single-entry Critical Alerts timeline with an `.after` reload policy.
    public static func alerts(_ data: WidgetData, now: Date, limit: Int) -> Timeline<CriticalAlertsEntry> {
        let entry = CriticalAlertsEntry(date: now, alerts: Array(data.alerts.prefix(limit)))
        return Timeline(entries: [entry], policy: .after(nextReload(after: now)))
    }
}
