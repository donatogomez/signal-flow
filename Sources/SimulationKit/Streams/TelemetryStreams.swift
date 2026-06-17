import Foundation

/// Drives one device's tick loop, pacing with `clock` and forwarding each item to `continuation`.
///
/// This is a free (non-isolated) function on purpose: when several of these run inside a `TaskGroup`,
/// each `await device.advance()` hops to its *own* device actor, so devices simulate genuinely
/// concurrently instead of serializing on a shared owner. Cancellation is structural — when the task
/// is cancelled, `clock.awaitTick` throws and the loop exits promptly.
func pumpDevice(
    _ device: SimulatedDeviceActor,
    clock: any SimulationClock,
    maxTicks: Int?,
    into continuation: AsyncStream<DeviceTelemetry>.Continuation
) async {
    var index = 0
    while maxTicks.map({ index < $0 }) ?? true {
        do {
            try await clock.awaitTick(index)
        } catch {
            break   // cancelled
        }
        for item in await device.advance() {
            continuation.yield(item)
        }
        index += 1
    }
}

public extension SimulatedDeviceActor {
    /// A cancellation-correct telemetry stream for this device.
    ///
    /// The producing task is cancelled when the consumer stops iterating (`onTermination`), and the
    /// loop also stops if its task is cancelled. Run exactly one stream per device actor — the actor's
    /// tick state advances as the stream is consumed.
    nonisolated func makeTelemetryStream(
        clock: any SimulationClock,
        maxTicks: Int? = nil
    ) -> AsyncStream<DeviceTelemetry> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await pumpDevice(self, clock: clock, maxTicks: maxTicks, into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
