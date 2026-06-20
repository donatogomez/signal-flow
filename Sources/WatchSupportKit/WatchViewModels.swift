import Foundation
import DomainKit
import SnapshotKit

/// Glanceable fleet summary for the watch's first screen — a pure projection of a ``WatchSnapshot``.
public struct FleetSummaryViewModel: Equatable, Sendable {
    public let online: Int
    public let warning: Int
    public let critical: Int
    public let offline: Int
    public let total: Int
    public let hasData: Bool
    public let alertCount: Int

    public init(_ snapshot: WatchSnapshot) {
        self.online = snapshot.fleet.online
        self.warning = snapshot.fleet.warning
        self.critical = snapshot.fleet.critical
        self.offline = snapshot.fleet.offline
        self.total = snapshot.fleet.total
        self.hasData = snapshot.hasData
        self.alertCount = snapshot.alerts.count
    }

    /// One-line status, severity-first, for a large glanceable headline.
    public var headline: String {
        guard hasData else { return loc("No data") }
        if critical > 0 { return loc("\(critical) critical") }
        if warning > 0 { return loc("\(warning) warning") }
        return loc("All clear")
    }

    /// True when there's something worth tapping into the Alerts screen for.
    public var hasAlerts: Bool { alertCount > 0 }
}

/// The Critical Alerts list — a pure projection that enforces the watch's severity hierarchy.
public struct AlertListViewModel: Equatable, Sendable {
    /// Alerts ordered for a watch: most severe first, then most recent. (`AlertSeverity` is `Comparable`.)
    public let alerts: [WidgetAlert]

    public init(_ snapshot: WatchSnapshot) {
        self.alerts = snapshot.alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.raisedAt > rhs.raisedAt
        }
    }

    public var isEmpty: Bool { alerts.isEmpty }
}
