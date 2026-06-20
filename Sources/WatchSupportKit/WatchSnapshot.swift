import Foundation
import SnapshotKit

/// The read model the watch app renders, derived from the persisted snapshot.
///
/// `hasData` distinguishes "the iPhone app hasn't populated the shared store yet" (empty state) from
/// "there is a fleet, and it happens to be all-healthy". The watch never computes any of this itself —
/// it's the same `SnapshotKit` aggregation the widgets and App Intents use.
public struct WatchSnapshot: Sendable, Equatable {
    public let fleet: FleetSummary
    public let alerts: [WidgetAlert]
    public let hasData: Bool

    public init(fleet: FleetSummary, alerts: [WidgetAlert], hasData: Bool) {
        self.fleet = fleet
        self.alerts = alerts
        self.hasData = hasData
    }

    /// No fleet has been persisted yet — the iPhone app needs to run first.
    public static let empty = WatchSnapshot(fleet: .empty, alerts: [], hasData: false)

    /// Builds a watch snapshot from a `SnapshotKit` read model. A fleet with no devices is treated as
    /// "no data yet" so the UI can show its empty state.
    public static func from(_ data: WidgetData) -> WatchSnapshot {
        WatchSnapshot(fleet: data.fleet, alerts: data.alerts, hasData: data.fleet.total > 0)
    }
}

/// Reads a ``WatchSnapshot`` from persisted state. Injectable so tests can drive it from an in-memory store.
public protocol WatchSnapshotProviding: Sendable {
    func load() async -> WatchSnapshot
}

/// Live provider: reads the shared App Group store through `SnapshotKit`'s reader (PersistenceKit →
/// SwiftData). It **never** starts simulation or live ingestion — it only observes what the iPhone app
/// has already persisted. If the store can't be read, it returns ``WatchSnapshot/empty``.
public struct PersistedWatchSnapshotProvider: WatchSnapshotProviding {
    private let makeReader: @Sendable () throws -> WidgetSnapshotReader

    public init() {
        self.makeReader = { try WidgetSnapshotReader.shared() }
    }

    /// Test seam: read through an injected reader (e.g. one over an in-memory `PersistenceStore`).
    public init(reader: WidgetSnapshotReader) {
        self.makeReader = { reader }
    }

    public func load() async -> WatchSnapshot {
        guard let reader = try? makeReader(), let data = try? await reader.read() else {
            return .empty
        }
        return .from(data)
    }
}
