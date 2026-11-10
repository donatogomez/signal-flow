import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
import Synchronization

/// iPhone side of the sync: activates `WCSession` and pushes the latest fleet snapshot to the paired
/// Watch via `updateApplicationContext` — the simplest reliable strategy for "always show the newest
/// state". The system coalesces to the latest context and delivers it even if the watch is asleep.
///
/// `@unchecked Sendable` is the deliberate, contained exception for bridging Apple's NSObject-based
/// `WCSessionDelegate`: its only mutable state is an `Atomic` flag, so it's safe to hand to `WCSession`.
/// WatchConnectivity is iOS/watchOS-only, so this whole file is `#if canImport(WatchConnectivity)`.
public final class PhoneSnapshotSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// Whether the last send failed, so a persistent failure is logged once, not every cadence tick.
    private let isFailing = Atomic<Bool>(false)

    public override init() { super.init() }

    public func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the snapshot as the session's application context (latest-wins). No-ops if the session isn't
    /// activated yet, or (on iPhone) no watch with the app is paired — expected states, not failures.
    /// The caller's periodic sync tries again on its next tick.
    public func send(_ snapshot: WatchSyncSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            let data = try WatchSnapshotCodec.encode(snapshot)
            try session.updateApplicationContext([WatchSnapshotCodec.applicationContextKey: data])
            if isFailing.exchange(false, ordering: .relaxed) {
                Log.watchSync.notice("Watch snapshot sync recovered")
            }
        } catch {
            if !isFailing.exchange(true, ordering: .relaxed) {
                Log.watchSync.error("Sending the watch snapshot failed: \(String(describing: error), privacy: .private)")
            }
        }
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Log.watchSync.error("WatchConnectivity activation failed: \(String(describing: error), privacy: .private)")
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

#else

/// Non-iOS stub (the macOS host that runs CI). Same API, no-ops, so the composition root calls it
/// unconditionally without `#if` at every call site.
public final class PhoneSnapshotSync: Sendable {
    public init() {}
    public func start() {}
    public func send(_ snapshot: WatchSyncSnapshot) {}
}

#endif
