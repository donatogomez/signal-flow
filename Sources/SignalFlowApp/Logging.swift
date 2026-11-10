import os

/// The app shell's unified-logging channels. Only startup outcomes are logged here; the data layer
/// logs its own failures where it handles them.
enum Log {
    static let lifecycle = Logger(subsystem: "com.signalflow.SignalFlow", category: "lifecycle")
    static let persistence = Logger(subsystem: "com.signalflow.SignalFlow", category: "persistence")
}
