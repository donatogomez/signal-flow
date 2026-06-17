import Foundation
import DomainKit

/// The complete behavioral recipe for a simulated device: its metrics and their signal models, plus
/// optional door, connectivity, and motion dynamics. Profiles are value types, so each device gets an
/// independent, mutable copy of the state.
public struct SimulationProfile: Sendable {
    public var assetKind: AssetKind
    public var metrics: [MetricSimulator]
    public var door: DoorBehavior?
    public var connectivity: ConnectivityBehavior
    public var motion: MotionBehavior?

    public init(
        assetKind: AssetKind,
        metrics: [MetricSimulator],
        door: DoorBehavior? = nil,
        connectivity: ConnectivityBehavior = .stable,
        motion: MotionBehavior? = nil
    ) {
        self.assetKind = assetKind
        self.metrics = metrics
        self.door = door
        self.connectivity = connectivity
        self.motion = motion
    }
}

// MARK: - Asset profiles

public extension SimulationProfile {

    /// Temperature drifts slowly on a day/night curve, humidity fluctuates, CO₂ spikes occasionally.
    static func greenhouse() -> SimulationProfile {
        SimulationProfile(
            assetKind: .greenhouse,
            metrics: [
                MetricSimulator(metric: .temperature, unit: .celsius, safeRange: 15...32, model: .diurnal(
                    Diurnal(baseline: 24, amplitude: 3.5, periodSeconds: 86_400,
                            noise: MeanReverting(value: 0, mean: 0, reversion: 0.2, volatility: 0.15, bounds: -3...3),
                            bounds: 8...42))),
                MetricSimulator(metric: .humidity, unit: .percent, safeRange: 40...80, model: .meanReverting(
                    MeanReverting(value: 60, mean: 60, reversion: 0.05, volatility: 1.2, bounds: 30...95))),
                MetricSimulator(metric: .carbonDioxide, unit: .partsPerMillion, safeRange: 380...1200, model: .spiking(
                    Spiking(baseline: MeanReverting(value: 450, mean: 450, reversion: 0.1, volatility: 8, bounds: 380...700),
                            spikeProbability: 0.02, spikeMagnitude: 300...750, decay: 0.85, bounds: 380...2000))),
            ],
            connectivity: ConnectivityBehavior(dropProbability: 0.002, outageDurationTicks: 2...6)
        )
    }

    /// Stable low temperature, door-open events that warm the cabin, GPS movement, signal fluctuation.
    static func refrigeratedTruck() -> SimulationProfile {
        SimulationProfile(
            assetKind: .refrigeratedTruck,
            metrics: [
                MetricSimulator(metric: .temperature, unit: .celsius, safeRange: 0...8, model: .meanReverting(
                    MeanReverting(value: 3, mean: 3, reversion: 0.15, volatility: 0.25, bounds: -5...18))),
                MetricSimulator(metric: .signalStrength, unit: .decibelMilliwatts, safeRange: -100...(-50), model: .meanReverting(
                    MeanReverting(value: -75, mean: -75, reversion: 0.1, volatility: 3, bounds: -110...(-50)))),
                MetricSimulator(metric: .batteryLevel, unit: .percent, model: .linearDrift(
                    LinearDrift(value: 100, perStep: -0.03, jitter: 0.02, bounds: 0...100, rechargeAt: 10, rechargeTo: 100))),
            ],
            door: DoorBehavior(openProbability: 0.012, openDurationTicks: 3...10, temperatureOffset: 7),
            connectivity: ConnectivityBehavior(dropProbability: 0.01, outageDurationTicks: 3...12),
            motion: MotionBehavior(latitude: 41.39, longitude: 2.16, heading: 0.8, speed: 0.0025, headingJitter: 0.2)
        )
    }

    /// A stable environment whose headline behavior is slow battery degradation.
    static func warehouse() -> SimulationProfile {
        SimulationProfile(
            assetKind: .warehouse,
            metrics: [
                MetricSimulator(metric: .temperature, unit: .celsius, safeRange: 12...28, model: .meanReverting(
                    MeanReverting(value: 20, mean: 20, reversion: 0.1, volatility: 0.1, bounds: 10...30))),
                MetricSimulator(metric: .humidity, unit: .percent, safeRange: 25...65, model: .meanReverting(
                    MeanReverting(value: 45, mean: 45, reversion: 0.05, volatility: 0.5, bounds: 20...70))),
                MetricSimulator(metric: .batteryLevel, unit: .percent, model: .linearDrift(
                    LinearDrift(value: 95, perStep: -0.05, jitter: 0.03, bounds: 0...100, rechargeAt: 5, rechargeTo: 100))),
            ],
            connectivity: ConnectivityBehavior(dropProbability: 0.001, outageDurationTicks: 2...5)
        )
    }

    /// Weather-like patterns with a larger temperature range, plus humidity and barometric pressure
    /// (a `custom` metric, demonstrating the open-ended metric model).
    static func environmentalStation() -> SimulationProfile {
        SimulationProfile(
            assetKind: .environmentalStation,
            metrics: [
                MetricSimulator(metric: .temperature, unit: .celsius, safeRange: -10...45, model: .diurnal(
                    Diurnal(baseline: 15, amplitude: 12, periodSeconds: 86_400,
                            noise: MeanReverting(value: 0, mean: 0, reversion: 0.15, volatility: 0.4, bounds: -5...5),
                            bounds: -25...55))),
                MetricSimulator(metric: .humidity, unit: .percent, safeRange: 15...95, model: .meanReverting(
                    MeanReverting(value: 70, mean: 70, reversion: 0.04, volatility: 1.5, bounds: 10...100))),
                MetricSimulator(metric: .custom("pressure"), unit: .hectopascals, safeRange: 980...1040, model: .meanReverting(
                    MeanReverting(value: 1013, mean: 1013, reversion: 0.05, volatility: 1.5, bounds: 960...1050))),
            ],
            connectivity: ConnectivityBehavior(dropProbability: 0.003, outageDurationTicks: 4...10)
        )
    }

    /// The profile for a given asset kind.
    static func make(for kind: AssetKind) -> SimulationProfile {
        switch kind {
        case .greenhouse: greenhouse()
        case .refrigeratedTruck, .coldChainContainer: refrigeratedTruck()
        case .warehouse: warehouse()
        case .industrialEquipment, .environmentalStation: environmentalStation()
        }
    }
}
