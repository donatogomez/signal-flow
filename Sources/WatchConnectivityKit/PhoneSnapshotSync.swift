import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

/// iPhone side of the sync: activates `WCSession` and pushes the latest fleet snapshot to the paired
/// Watch via `updateApplicationContext` — the simplest reliable strategy for "always show the newest
/// state". The system coalesces to the latest context and delivers it even if the watch is asleep.
///
/// `@unchecked Sendable` is the deliberate, contained exception for bridging Apple's NSObject-based
/// `WCSessionDelegate`: the type holds **no mutable state**, so it's safe to hand to `WCSession`.
/// WatchConnectivity is iOS/watchOS-only, so this whole file is `#if canImport(WatchConnectivity)`.
public final class PhoneSnapshotSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    public override init() { super.init() }

    public func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the snapshot as the session's application context (latest-wins). No-ops if the session isn't
    /// activated yet — the caller's periodic sync will retry once it is.
    public func send(_ snapshot: WatchSyncSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = try? WatchSnapshotCodec.encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchSnapshotCodec.applicationContextKey: data])
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

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
