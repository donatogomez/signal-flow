import Foundation
import os

/// **Temporary** DEBUG-only diagnostics for the WatchConnectivity sync path.
///
/// In release builds `log(_:)` is an inlinable no-op and the `@autoclosure` message is never evaluated,
/// so the property reads inside it (session flags, snapshot counts) cost nothing. View in Console.app /
/// the Xcode debug console by filtering on subsystem `com.signalflow.app`, category `WatchSync`.
public enum SyncLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.signalflow.app", category: "WatchSync")

    public static func log(_ message: @autoclosure () -> String) {
        let text = message()
        logger.log("⌚️ \(text, privacy: .public)")
    }
    #else
    @inline(__always) public static func log(_ message: @autoclosure () -> String) {}
    #endif
}
