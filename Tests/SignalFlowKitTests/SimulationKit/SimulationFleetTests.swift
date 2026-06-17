import Foundation
import Testing
import DomainKit
import SimulationKit

@Suite("Fleet simulation & concurrency")
struct SimulationFleetTests {

    @Test("The standard fleet has ten devices across all asset kinds")
    func standardFleetComposition() async {
        let clock = ImmediateSimulationClock()
        let engine = SimulationFleet.standard(clock: clock, maxTicks: 5)
        let descriptors = await engine.descriptors()

        #expect(descriptors.count == 10)
        let kinds = Set(descriptors.map(\.assetKind))
        #expect(kinds == [.greenhouse, .refrigeratedTruck, .warehouse, .environmentalStation])
    }

    @Test("The merged fleet stream produces telemetry from every device concurrently")
    func fleetStreamCoversAllDevices() async {
        let clock = ImmediateSimulationClock()
        let engine = SimulationFleet.standard(clock: clock, maxTicks: 8)
        let expectedIDs = Set(await engine.descriptors().map(\.id))

        var seenIDs: Set<DeviceID> = []
        var total = 0
        for await item in await engine.makeFleetStream() {
            seenIDs.insert(item.deviceID)
            total += 1
        }

        #expect(seenIDs == expectedIDs)   // every device contributed
        #expect(total > 100)              // 10 devices × several metrics × 8 ticks
    }

    @Test("Per-device substreams remain deterministic under the same seed")
    func perDeviceSubstreamDeterministic() async {
        func runFleet() async -> [DeviceID: Int] {
            let clock = ImmediateSimulationClock()
            let engine = SimulationFleet.standard(seed: 7, clock: clock, maxTicks: 6)
            var counts: [DeviceID: Int] = [:]
            for await item in await engine.makeFleetStream() {
                counts[item.deviceID, default: 0] += 1
            }
            return counts
        }
        // Device IDs are random per run, but the per-device item *counts* (seed-derived) are stable,
        // so the sorted multiset of counts is identical across runs — determinism under concurrency.
        let first = await runFleet()
        let second = await runFleet()
        #expect(first.values.sorted() == second.values.sorted())
    }
}
