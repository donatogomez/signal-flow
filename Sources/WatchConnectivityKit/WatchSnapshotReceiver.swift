import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Watch side of the sync: activates `WCSession`, receives the iPhone's application context, decodes it,
/// persists it locally (latest-wins via the store), and notifies the UI to refresh.
///
/// `@unchecked Sendable` is the contained exception for bridging Apple's `WCSessionDelegate`: all stored
/// state is **immutable** (`let store`, `let onUpdate`), set before activation and only read afterwards,
/// so it's safe to hand to `WCSession` and to touch from its background delegate callbacks.
public final class WatchSnapshotReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let store: WatchSyncSnapshotStore
    private let onUpdate: @Sendable () -> Void

    public init(store: WatchSyncSnapshotStore, onUpdate: @escaping @Sendable () -> Void) {
        self.store = store
        self.onUpdate = onUpdate
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Log.watchSync.error("WatchConnectivity activation failed: \(String(describing: error), privacy: .private)")
        }
        // The OS retains the latest application context across launches — ingest whatever's already there.
        ingest(session.receivedApplicationContext)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }

    // Required by WCSessionDelegate on iOS (this type compiles for iOS too, though it only runs on watchOS).
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    private func ingest(_ context: [String: Any]) {
        guard let data = context[WatchSnapshotCodec.applicationContextKey] as? Data else { return } // nothing synced yet
        let snapshot: WatchSyncSnapshot
        do {
            snapshot = try WatchSnapshotCodec.decode(data)
        } catch {
            // Typically a phone/watch version mismatch; the last stored snapshot stays on screen.
            Log.watchSync.error("Received watch snapshot couldn't be decoded: \(String(describing: error), privacy: .private)")
            return
        }
        guard store.ingest(snapshot) else { return }   // stale, or couldn't be saved (logged by the store)
        onUpdate()
    }
}

#else

/// Non-watchOS stub (the macOS host that runs CI). Same API, no-ops.
public final class WatchSnapshotReceiver: Sendable {
    public init(store: WatchSyncSnapshotStore, onUpdate: @escaping @Sendable () -> Void) {}
    public func start() {}
}

#endif
