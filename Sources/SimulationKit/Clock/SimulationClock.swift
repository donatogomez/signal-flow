import Foundation
import CoreKit

/// Abstracts *simulated time* away from wall-clock time.
///
/// Two concerns are separated deliberately:
/// - **Mapping** simulated instants: `instant(forTick:)` is pure — tick 0 is `origin`, each tick
///   advances by `tick`. Telemetry timestamps come from here, never from `Date()`, so the *data* a
///   simulation produces is identical regardless of when or how fast it runs.
/// - **Pacing**: `awaitTick(_:)` controls how fast ticks are delivered in real time, and is
///   cancellation-aware. Live runs sleep (accelerated); tests run immediately.
///
/// This lets the same simulation drive a real-time demo and a deterministic, instant test.
public protocol SimulationClock: Sendable {
    /// The simulated instant of tick 0.
    var origin: Date { get }
    /// How much simulated time each tick represents.
    var tick: Duration { get }
    /// The simulated instant of tick `index` (pure, deterministic).
    func instant(forTick index: Int) -> Date
    /// Suspends until tick `index` should fire. Throws `CancellationError` if cancelled.
    func awaitTick(_ index: Int) async throws
}

public extension SimulationClock {
    func instant(forTick index: Int) -> Date {
        origin.addingTimeInterval(tick.inSeconds * Double(index))
    }
}
