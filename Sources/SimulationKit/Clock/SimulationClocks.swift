import Foundation

public extension Date {
    /// The default simulated origin (a fixed instant), so runs are reproducible by default.
    static let simulationOrigin = Date(timeIntervalSince1970: 1_700_000_000)
}

/// Delivers ticks as fast as the consumer can take them — no sleeping.
///
/// Used for deterministic tests and bulk generation: timestamps still come from `instant(forTick:)`,
/// so output is identical to a real-time run, just produced instantly. It still yields cooperatively
/// so cancellation is honored promptly.
public struct ImmediateSimulationClock: SimulationClock {
    public let origin: Date
    public let tick: Duration

    public init(origin: Date = .simulationOrigin, tick: Duration = .seconds(60)) {
        self.origin = origin
        self.tick = tick
    }

    public func awaitTick(_ index: Int) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

/// Delivers ticks paced against the real clock, scaled by `timeScale`.
///
/// `timeScale` is simulated-seconds-per-real-second: a 60s tick at `timeScale = 600` fires every
/// 100 ms of wall time, so an hour of telemetry plays out in six seconds. Sleeping is cancellation-
/// aware (`Task.sleep`), so a cancelled stream stops promptly.
public struct AcceleratedSimulationClock: SimulationClock {
    public let origin: Date
    public let tick: Duration
    public let timeScale: Double

    public init(origin: Date = .simulationOrigin, tick: Duration = .seconds(60), timeScale: Double = 600) {
        precondition(timeScale > 0, "timeScale must be positive")
        self.origin = origin
        self.tick = tick
        self.timeScale = timeScale
    }

    public func awaitTick(_ index: Int) async throws {
        let realSeconds = tick.inSeconds / timeScale
        if realSeconds > 0 {
            try await Task.sleep(for: .seconds(realSeconds))
        } else {
            try Task.checkCancellation()
        }
    }
}
