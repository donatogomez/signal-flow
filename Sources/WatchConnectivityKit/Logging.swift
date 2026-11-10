import os

/// WatchConnectivityKit's unified-logging channel. Sync runs on a short cadence, so repeated failures
/// are logged once per episode rather than once per attempt.
enum Log {
    static let watchSync = Logger(subsystem: "com.signalflow.SignalFlow", category: "watch-sync")
}
