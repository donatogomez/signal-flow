import Foundation
import Observation
import WatchConnectivityKit

/// Ties WatchConnectivity to the watch UI: it owns the ``WatchStore`` (backed by the synced-snapshot
/// store) and a ``WatchConnectivityKit/WatchSnapshotReceiver`` that persists incoming iPhone snapshots and
/// triggers a UI refresh. The watch `@main` shell holds one of these and calls ``start()``.
///
/// WatchConnectivity itself stays fully inside `WatchConnectivityKit`; this coordinator only wires the
/// receiver's "new snapshot" signal to `store.refresh()` on the main actor.
@MainActor
@Observable
public final class WatchSyncCoordinator {
    public let store: WatchStore
    private let receiver: WatchSnapshotReceiver

    public init(snapshotStore: WatchSyncSnapshotStore = WatchSyncSnapshotStore()) {
        let store = WatchStore(provider: SyncedWatchSnapshotProvider(store: snapshotStore))
        self.store = store
        self.receiver = WatchSnapshotReceiver(store: snapshotStore, onUpdate: {
            Task { @MainActor in await store.refresh() }
        })
    }

    /// Activates the WatchConnectivity session and loads whatever's already been synced/persisted.
    public func start() async {
        receiver.start()
        await store.refresh()
    }
}
