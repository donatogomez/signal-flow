import Foundation
import Testing
import SimulationKit

@Suite("Simulation clock")
struct SimulationClockTests {

    @Test("Tick instants advance by the tick duration from the origin")
    func instantsAdvance() {
        let origin = Date(timeIntervalSince1970: 1_000)
        let clock = ImmediateSimulationClock(origin: origin, tick: .seconds(60))
        #expect(clock.instant(forTick: 0) == origin)
        #expect(clock.instant(forTick: 1) == origin.addingTimeInterval(60))
        #expect(clock.instant(forTick: 10) == origin.addingTimeInterval(600))
    }

    @Test("Immediate clock does not wait")
    func immediateClockDoesNotWait() async throws {
        let clock = ImmediateSimulationClock()
        let start = ContinuousClock().now
        for index in 0..<1000 { try await clock.awaitTick(index) }
        let elapsed = ContinuousClock().now - start
        #expect(elapsed < .seconds(1))
    }

    @Test("Accelerated clock paces relative to the time scale")
    func acceleratedClockPaces() async throws {
        // 60s tick at timeScale 600 → 0.1s per tick; 3 ticks ≈ 0.3s.
        let clock = AcceleratedSimulationClock(tick: .seconds(60), timeScale: 600)
        let start = ContinuousClock().now
        for index in 0..<3 { try await clock.awaitTick(index) }
        let elapsed = ContinuousClock().now - start
        #expect(elapsed >= .milliseconds(250))
        #expect(elapsed < .seconds(2))
    }
}
