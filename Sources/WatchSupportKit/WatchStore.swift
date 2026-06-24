import Foundation
import Observation
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

    public init(provider: any WatchSnapshotProviding = PersistedWatchSnapshotProvider()) {
        self.provider = provider
    }

    public var fleet: FleetSummaryViewModel { FleetSummaryViewModel(snapshot) }
    public var alertList: AlertListViewModel { AlertListViewModel(snapshot) }
    public var deviceList: DeviceListViewModel { DeviceListViewModel(snapshot) }
    public var hasData: Bool { snapshot.hasData }

    /// Re-reads the persisted snapshot. Cheap and idempotent; safe to call from `.task`/refresh.
    public func refresh() async {
        snapshot = await provider.load()
        phase = .loaded
    }
}
