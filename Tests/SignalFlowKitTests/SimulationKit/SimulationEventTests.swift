import Foundation
import Testing
import DomainKit
import SimulationKit

@Suite("Event generation & actor isolation")
struct SimulationEventTests {

    private let clock = ImmediateSimulationClock()

    private func collect(_ device: SimulatedDeviceActor, ticks: Int) async -> [DeviceTelemetry] {
        var items: [DeviceTelemetry] = []
        for await item in device.makeTelemetryStream(clock: clock, maxTicks: ticks) { items.append(item) }
        return items
    }

    private func events(_ items: [DeviceTelemetry]) -> [DeviceEvent] {
        items.compactMap { if case .event(let event) = $0 { return event } else { return nil } }
    }

    @Test("A door that always opens emits door-opened and door-closed events")
    func doorEvents() async {
        let profile = SimulationProfile(
            assetKind: .refrigeratedTruck,
            metrics: [MetricSimulator(metric: .temperature, unit: .celsius, model: .meanReverting(
                MeanReverting(value: 3, mean: 3, reversion: 0.1, volatility: 0.1, bounds: -5...15)))],
            door: DoorBehavior(openProbability: 1, openDurationTicks: 2...2, temperatureOffset: 7)
        )
        let device = SimulatedDeviceActor(name: "Reefer", assetKind: .refrigeratedTruck, profile: profile, clock: clock, seed: 1)
        let kinds = events(await collect(device, ticks: 6)).map(\.kind)
        #expect(kinds.contains(.doorOpened))
        #expect(kinds.contains(.doorClosed))
    }

    @Test("A forced outage emits a disconnect, then a reconnect, and is silent in between")
    func connectivityEvents() async {
        let profile = SimulationProfile(
            assetKind: .warehouse,
            metrics: [MetricSimulator(metric: .temperature, unit: .celsius, model: .meanReverting(
                MeanReverting(value: 20, mean: 20, reversion: 0.1, volatility: 0.1, bounds: 10...30)))],
            connectivity: ConnectivityBehavior(dropProbability: 1, outageDurationTicks: 2...2)
        )
        let device = SimulatedDeviceActor(name: "WH", assetKind: .warehouse, profile: profile, clock: clock, seed: 1)
        let items = await collect(device, ticks: 6)
        let kinds = events(items).map(\.kind)
        #expect(kinds.contains(.disconnected))
        #expect(kinds.contains(.connected))
        // No readings are produced while offline: the first tick drops, so the first item is the event.
        if case .event(let first) = items.first { #expect(first.kind == .disconnected) } else { Issue.record("expected a disconnect first") }
    }

    @Test("A draining battery emits a battery-low event")
    func batteryLowEvent() async {
        let profile = SimulationProfile(
            assetKind: .warehouse,
            metrics: [MetricSimulator(metric: .batteryLevel, unit: .percent, model: .linearDrift(
                LinearDrift(value: 18, perStep: -2, jitter: 0, bounds: 0...100)))]
        )
        let device = SimulatedDeviceActor(name: "WH", assetKind: .warehouse, profile: profile, clock: clock, seed: 1)
        let details = events(await collect(device, ticks: 5))
        #expect(details.contains { $0.kind == .custom("battery_low") })
    }

    @Test("Leaving the safe range emits a threshold-exceeded event")
    func thresholdEvent() async {
        let profile = SimulationProfile(
            assetKind: .greenhouse,
            metrics: [MetricSimulator(metric: .temperature, unit: .celsius, safeRange: 0...10, model: .meanReverting(
                MeanReverting(value: 0, mean: 100, reversion: 1, volatility: 0, bounds: 0...200)))]
        )
        let device = SimulatedDeviceActor(name: "GH", assetKind: .greenhouse, profile: profile, clock: clock, seed: 1)
        let kinds = events(await collect(device, ticks: 4)).map(\.kind)
        #expect(kinds.contains(.custom("threshold_exceeded")))
    }

    @Test("The truck profile emits position updates as it moves")
    func locationUpdates() async {
        let device = SimulatedDeviceActor(name: "Reefer", assetKind: .refrigeratedTruck, profile: .refrigeratedTruck(), clock: clock, seed: 5)
        let locations = await collect(device, ticks: 10).compactMap { item -> Location? in
            if case .location(_, let location, _) = item { return location } else { return nil }
        }
        #expect(locations.count >= 8)
        #expect(locations.first != locations.last)   // it actually moved
    }

    @Test("The device actor owns and advances its tick state in order")
    func actorAdvancesState() async {
        let device = SimulatedDeviceActor(name: "GH", assetKind: .greenhouse, profile: .greenhouse(), clock: clock, seed: 3)
        // Each await hops onto the actor; timestamps must be strictly increasing tick-by-tick.
        let firstBatch = await device.advance()
        let secondBatch = await device.advance()
        let firstTime = try? #require(firstBatch.first?.timestamp)
        let secondTime = try? #require(secondBatch.first?.timestamp)
        if let firstTime, let secondTime { #expect(secondTime > firstTime) }
    }
}
