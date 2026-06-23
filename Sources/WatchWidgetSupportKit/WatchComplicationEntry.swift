import Foundation
import DomainKit
import SnapshotKit
import WatchConnectivityKit

/// Data freshness of the watch's last synced snapshot, as the complication sees it.
public enum WatchSnapshotFreshness: Equatable, Sendable {
    /// Nothing has synced yet — the complication shows a neutral "no data" state.
    case noData
    /// Synced within the stale threshold.
    case fresh
    /// Older than the stale threshold — still shown (last-known data), but flagged.
    case stale
}

/// A single, glanceable fleet-health entry for the watch complication / Smart Stack widget.
///
/// A pure value type derived deterministically from a ``WatchConnectivityKit/WatchSyncSnapshot`` — no
/// WidgetKit, no I/O — so the projection (counts, top alert, freshness, relevance) is unit-tested on the
/// macOS host. WidgetKit `TimelineEntry` conformance (and Smart Stack relevance) is added conditionally
/// below so the type still compiles and tests on a machine without watchOS.
public struct WatchComplicationEntry: Equatable, Sendable {
    public let date: Date
    public let online: Int
    public let warning: Int
    public let critical: Int
    public let offline: Int
    public let total: Int
    /// The single most pressing critical alert, if any (most severe, then most recent).
    public let topAlert: WidgetAlert?
    /// The freshness anchor: the newest reading time if known, else the sync time. Drives the "last
    /// seen / updated" label and the stale treatment.
    public let referenceDate: Date?
    public let freshness: WatchSnapshotFreshness

    public init(
        date: Date,
        online: Int,
        warning: Int,
        critical: Int,
        offline: Int,
        topAlert: WidgetAlert?,
        referenceDate: Date?,
        freshness: WatchSnapshotFreshness
    ) {
        self.date = date
        self.online = online
        self.warning = warning
        self.critical = critical
        self.offline = offline
        self.total = online + warning + critical + offline
        self.topAlert = topAlert
        self.referenceDate = referenceDate
        self.freshness = freshness
    }

    public var hasData: Bool { total > 0 && freshness != .noData }
    public var isStale: Bool { freshness == .stale }

    /// Smart Stack relevance: high when criticals exist, lower for warnings, and a small floor when all
    /// nominal (present but quiet). Stale data is damped so a fresh-but-quiet fleet can still out-rank an
    /// old alarming one. Deterministic, so it's unit-tested.
    public var relevanceScore: Float {
        guard hasData else { return 0 }
        var score = Float(critical) * 10 + Float(warning) * 3
        if critical == 0 && warning == 0 { score = 0.5 } // all nominal: surface low, never zero
        if freshness == .stale { score *= 0.5 }
        return score
    }

    /// Gallery/preview placeholder.
    public static let placeholder = WatchComplicationEntry(
        date: .now, online: 8, warning: 1, critical: 1, offline: 0,
        topAlert: nil, referenceDate: .now, freshness: .fresh
    )
}

/// Builds the complication entry from the watch's synced snapshot. Pure and deterministic (no WidgetKit,
/// no I/O) so it's fully unit-testable; the watchOS `TimelineProvider` is a thin shell over this.
public enum WatchComplicationModel {
    /// Snapshots older than this read as **stale** (still shown, flagged).
    public static let staleThreshold: TimeInterval = 30 * 60

    /// How long a complication entry stays valid before WidgetKit should request a fresh one. Like the
    /// iOS widgets, the watch app refreshes the synced store far more often than a complication can
    /// reload, so we ask for a single entry now and a reload after a fixed interval.
    public static let refreshInterval: TimeInterval = 15 * 60

    /// Projects a snapshot into a complication entry as of `now`.
    public static func entry(from snapshot: WatchSyncSnapshot, now: Date) -> WatchComplicationEntry {
        guard snapshot.hasData else {
            return WatchComplicationEntry(
                date: now, online: 0, warning: 0, critical: 0, offline: 0,
                topAlert: nil, referenceDate: nil, freshness: .noData
            )
        }

        let fleet = snapshot.fleet
        let reference = fleet.lastUpdated ?? snapshot.lastUpdated
        let freshness: WatchSnapshotFreshness =
            now.timeIntervalSince(reference) <= staleThreshold ? .fresh : .stale

        let topAlert = snapshot.criticalAlerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.raisedAt > rhs.raisedAt
        }.first

        return WatchComplicationEntry(
            date: now,
            online: fleet.online,
            warning: fleet.warning,
            critical: fleet.critical,
            offline: fleet.offline,
            topAlert: topAlert,
            referenceDate: reference,
            freshness: freshness
        )
    }

    /// The next time WidgetKit should request a reload after producing an entry at `date`.
    public static func nextReload(after date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }
}

#if canImport(WidgetKit)
import WidgetKit

extension WatchComplicationEntry: TimelineEntry {
    /// Bridges the pure ``relevanceScore`` into WidgetKit's Smart Stack ranking.
    public var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: relevanceScore)
    }
}
#endif
