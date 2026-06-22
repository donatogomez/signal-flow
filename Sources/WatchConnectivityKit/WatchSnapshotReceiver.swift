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
        SyncLog.log("watch: receiver start() — WCSession.isSupported=\(WCSession.isSupported())")
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        SyncLog.log("watch: activate() requested — state=\(session.activationState.rawValue)")
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        SyncLog.log("watch: activationDidComplete — state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "nil")")
        // The OS retains the latest application context across launches — ingest whatever's already there.
        ingest(session.receivedApplicationContext)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        SyncLog.log("watch: didReceiveApplicationContext — keys=[\(Array(applicationContext.keys).joined(separator: ", "))]")
        ingest(applicationContext)
    }

    // Required by WCSessionDelegate on iOS (this type compiles for iOS too, though it only runs on watchOS).
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    private func ingest(_ context: [String: Any]) {
        guard let data = context[WatchSnapshotCodec.applicationContextKey] as? Data else {
            SyncLog.log("watch: ingest — no snapshot data under key '\(WatchSnapshotCodec.applicationContextKey)'")
            return
        }
        guard let snapshot = try? WatchSnapshotCodec.decode(data) else {
            SyncLog.log("watch: ingest — decode failed (\(data.count) bytes)")
            return
        }
        let stored = store.ingest(snapshot)
        SyncLog.log("watch: ingest — devices=\(snapshot.devices.count) criticalAlerts=\(snapshot.criticalAlerts.count) persisted=\(stored) lastUpdated=\(snapshot.lastUpdated)")
        guard stored else { return }   // ignore stale snapshots
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
