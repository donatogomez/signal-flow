import Foundation
import Observation
import DomainKit
import SnapshotKit

/// The watch app's single source of UI state. Thin by design: it loads a ``WatchSnapshot`` from the
/// injected provider and exposes the pure view models — it holds **no** business logic of its own.
@MainActor
@Observable
public final class WatchStore {
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
    }

    public private(set) var phase: Phase = .loading
    public private(set) var snapshot: WatchSnapshot = .empty

    private let provider: any WatchSnapshotProviding

    /// When each active alert was *first seen on this watch*, keyed by its stable id. The simulated
    /// `raisedAt` is in a 600×, past-epoch clock that can't be compared to wall time, so the inbox ages
    /// each alert by how long it has actually been showing here — a natural "0 min → 2 min" that the
    /// operator can trust. Pruned when an alert clears, so a re-raised alert starts fresh.
    private var alertFirstSeen: [AlertID: Date] = [:]

    public init(provider: any WatchSnapshotProviding = PersistedWatchSnapshotProvider()) {
        self.provider = provider
    }

    public var fleet: FleetSummaryViewModel { FleetSummaryViewModel(snapshot) }
    public var alertList: AlertListViewModel { AlertListViewModel(snapshot) }
    public var deviceList: DeviceListViewModel { DeviceListViewModel(snapshot) }
    public var hasData: Bool { snapshot.hasData }

    /// When the given alert first appeared on this watch (for its real-time age). Defaults to now for an
    /// alert we're seeing this very refresh.
    public func firstSeen(_ id: AlertID, now: Date = .now) -> Date {
        alertFirstSeen[id] ?? now
    }

    /// Re-reads the persisted snapshot. Cheap and idempotent; safe to call from `.task`/refresh.
    public func refresh() async {
        snapshot = await provider.load()
        reconcileAlertAges()
        phase = .loaded
    }

    /// Stamp newly-seen alerts and forget cleared ones, so `firstSeen` tracks the active set.
    private func reconcileAlertAges(now: Date = .now) {
        let activeIDs = Set(snapshot.alerts.map(\.id))
        alertFirstSeen = alertFirstSeen.filter { activeIDs.contains($0.key) }
        for id in activeIDs where alertFirstSeen[id] == nil { alertFirstSeen[id] = now }
    }
}
