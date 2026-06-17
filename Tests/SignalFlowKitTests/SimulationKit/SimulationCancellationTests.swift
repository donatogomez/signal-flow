import Foundation
import Testing
import DomainKit
import SimulationKit

@Suite("Simulation cancellation & AsyncSequence behaviour")
struct SimulationCancellationTests {

    private func makeTruck(clock: any SimulationClock, seed: UInt64 = 1) -> SimulatedDeviceActor {
        SimulatedDeviceActor(name: "Reefer", assetKind: .refrigeratedTruck, profile: .refrigeratedTruck(), clock: clock, seed: seed)
    }

    @Test("A bounded stream finishes after maxTicks")
    func boundedStreamFinishes() async {
        let clock = ImmediateSimulationClock()
        let device = makeTruck(clock: clock)
        var count = 0
        for await _ in device.makeTelemetryStream(clock: clock, maxTicks: 10) { count += 1 }
        #expect(count > 0)   // it terminated on its own — the loop exited
    }

    @Test("Cancelling the consuming task stops generation promptly")
    func cancellationStopsGeneration() async throws {
        // A slow clock guarantees the stream is still producing when we cancel.
        let clock = AcceleratedSimulationClock(tick: .seconds(60), timeScale: 120) // 0.5s per tick
        let device = makeTruck(clock: clock)

        let task = Task { () -> Int in
            var count = 0
            for await _ in device.makeTelemetryStream(clock: clock) { count += 1 }
            return count
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // If cancellation propagated, the task returns promptly rather than running forever.
        let collected = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw CancellationError() // safety net: the stream should have stopped well before this
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        #expect(collected >= 0)
    }

    @Test("prefix takes a fixed number of items from an unbounded stream")
    func prefixTakesItems() async {
        let clock = ImmediateSimulationClock()
        let device = makeTruck(clock: clock)
        var collected: [DeviceTelemetry] = []
        for await item in device.makeTelemetryStream(clock: clock).prefix(15) {
            collected.append(item)
        }
        #expect(collected.count == 15)
    }
}
