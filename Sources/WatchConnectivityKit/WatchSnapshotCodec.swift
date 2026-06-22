import Foundation

/// Encodes/decodes the watch sync snapshot with `Codable` (`JSONEncoder`/`JSONDecoder`) — **never**
/// `JSONSerialization`. Both the iPhone (encode) and the Watch (decode) go through this one type, so the
/// wire format can't drift between the two sides.
public enum WatchSnapshotCodec {
    public static func encode(_ snapshot: WatchSyncSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> WatchSyncSnapshot {
        try JSONDecoder().decode(WatchSyncSnapshot.self, from: data)
    }

    /// The dictionary key used inside the WCSession application context.
    public static let applicationContextKey = "fleetSnapshot"
}
