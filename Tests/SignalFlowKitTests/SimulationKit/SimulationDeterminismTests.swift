import Foundation
import Testing
import DomainKit
import SimulationKit

@Suite("Simulation determinism")
struct SimulationDeterminismTests {

    /// Collects a full device run with a fixed identity so two runs are comparable.
    private func run(seed: UInt64, ticks: Int = 120) async -> [DeviceTelemetry] {
        let clock = ImmediateSimulationClock()
        let device = SimulatedDeviceActor(
            id: DeviceID(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!),
            assetID: AssetID(UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!),
            name: "Reefer 12",
            assetKind: .refrigeratedTruck,
            profile: .refrigeratedTruck(),
            clock: clock,
            seed: seed
        )
        var items: [DeviceTelemetry] = []
        for await item in device.makeTelemetryStream(clock: clock, maxTicks: ticks) {
            items.append(item)
        }
        return items
    }

    @Test("Identical seed and identity produce identical telemetry")
    func sameSeedIdenticalOutput() async {
        let first = await run(seed: 42)
        let second = await run(seed: 42)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Different seeds produce different telemetry")
    func differentSeedsDiffer() async {
        let a = await run(seed: 42)
        let b = await run(seed: 43)
        #expect(a != b)
    }

    @Test("Telemetry evolves gradually, not wildly")
    func gradualEvolution() async {
        let items = await run(seed: 42, ticks: 200)
        // Consecutive temperature readings should never jump more than a few degrees per tick.
        let temperatures = items.compactMap { item -> Double? in
            if case .reading(let reading) = item, reading.metric == .temperature { return reading.value.magnitude }
            return nil
        }
        #expect(temperatures.count > 50)
        for (previous, next) in zip(temperatures, temperatures.dropFirst()) {
            #expect(abs(next - previous) < 9, "temperature jumped from \(previous) to \(next)")
        }
    }

    @Test("Reading timestamps come from simulated time, not the wall clock")
    func timestampsAreSimulated() async {
        let items = await run(seed: 42, ticks: 5)
        let origin = Date.simulationOrigin
        for item in items {
            #expect(item.timestamp >= origin)
            #expect(item.timestamp < origin.addingTimeInterval(5 * 60 + 1))
        }
    }
}
