import Foundation

/// Persists the latest received ``WatchSyncSnapshot`` **locally on the watch**, as a `Codable` JSON file.
///
/// The watch can't read the iPhone's SwiftData store (App Groups don't cross the device boundary — see
/// docs/27), so the synced snapshot is the watch's only source of truth and must survive relaunches.
/// A single small file is the simplest reliable store for a portfolio app; no SwiftData schema needed.
public final class WatchSyncSnapshotStore: Sendable {
    private let fileURL: URL

    /// Inject a file URL (tests use a temp directory); the default lives in the App Group container when
    /// available, else Caches.
    public init(fileURL: URL = WatchSyncSnapshotStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// The saved snapshot, or `nil` if none has been received yet or the file can't be decoded (then
    /// the next received snapshot replaces it).
    public func load() -> WatchSyncSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil } // no snapshot received yet
        do {
            return try WatchSnapshotCodec.decode(data)
        } catch {
            Log.watchSync.error("Saved watch snapshot couldn't be decoded: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    public func save(_ snapshot: WatchSyncSnapshot) throws {
        let data = try WatchSnapshotCodec.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Stores `snapshot` only if it's **newer** than what's already saved (latest-wins; stale snapshots
    /// from out-of-order delivery are ignored). Returns whether it was stored: `false` for a stale
    /// snapshot and for one that couldn't be written.
    @discardableResult
    public func ingest(_ snapshot: WatchSyncSnapshot) -> Bool {
        if let existing = load(), existing.lastUpdated >= snapshot.lastUpdated { return false }
        do {
            try save(snapshot)
            return true
        } catch {
            Log.watchSync.error("Saving the watch snapshot failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private static let appGroupIdentifier = "group.com.signalflow.shared"
    private static let fileName = "watch-fleet-snapshot.json"

    public static func defaultFileURL() -> URL {
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appending(path: fileName)
    }
}
