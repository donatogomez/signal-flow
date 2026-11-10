import os

/// DataKit's unified-logging channels.
///
/// Failures are logged where they are handled and can be interpreted — never per reading, and never
/// for expected cancellation. Error descriptions are `.private`: they can carry identifiers.
enum Log {
    static let persistence = Logger(subsystem: "com.signalflow.SignalFlow", category: "persistence")
}
