import Foundation
import CoreKit
import DomainKit

/// Simulates one metric on a device: which `SignalModel` drives it, its unit, and an optional safe
/// range whose breach (rising edge) is reported so the device can emit a "threshold exceeded" event.
public struct MetricSimulator: Sendable {
    public enum Model: Sendable {
        case meanReverting(MeanReverting)
        case diurnal(Diurnal)
        case linearDrift(LinearDrift)
        case spiking(Spiking)
    }

    public let metric: MetricKind
    public let unit: MeasurementUnit
    public let safeRange: ClosedRange<Double>?
    public var model: Model
    private var wasInsideSafeRange = true

    public init(metric: MetricKind, unit: MeasurementUnit, safeRange: ClosedRange<Double>? = nil, model: Model) {
        self.metric = metric
        self.unit = unit
        self.safeRange = safeRange
        self.model = model
    }

    public struct Sample: Sendable {
        public let magnitude: Double
        public let breachedSafeRange: Bool
        public let recharged: Bool
    }

    /// Advances the metric one step. `offset` lets the environment nudge the signal (e.g. an open
    /// truck door warming the cabin) without the model knowing why.
    public mutating func sample(sinceOrigin seconds: Double, offset: Double, using rng: inout SeededRandomNumberGenerator) -> Sample {
        let magnitude: Double
        var recharged = false

        switch model {
        case .meanReverting(var m):
            magnitude = m.advance(offset: offset, using: &rng)
            model = .meanReverting(m)
        case .diurnal(var d):
            magnitude = d.advance(sinceOrigin: seconds, offset: offset, using: &rng)
            model = .diurnal(d)
        case .linearDrift(var l):
            let result = l.advance(using: &rng)
            magnitude = result.value
            recharged = result.recharged
            model = .linearDrift(l)
        case .spiking(var s):
            magnitude = s.advance(using: &rng)
            model = .spiking(s)
        }

        var breached = false
        if let safeRange {
            let inside = safeRange.contains(magnitude)
            breached = wasInsideSafeRange && !inside   // rising edge only
            wasInsideSafeRange = inside
        }

        return Sample(magnitude: magnitude, breachedSafeRange: breached, recharged: recharged)
    }

    /// Applies a one-off per-device offset to the starting value so identical profiles still differ.
    mutating func applyInitialVariation(using rng: inout SeededRandomNumberGenerator) {
        let nudge = rng.nextGaussian(standardDeviation: 1)
        switch model {
        case .meanReverting(var m): m.value = (m.value + nudge).clamped(to: m.bounds); model = .meanReverting(m)
        case .diurnal(var d): d.noise.value = (d.noise.value + nudge).clamped(to: d.noise.bounds); model = .diurnal(d)
        case .linearDrift(var l): l.value = (l.value + nudge).clamped(to: l.bounds); model = .linearDrift(l)
        case .spiking(var s): s.baseline.value = (s.baseline.value + nudge).clamped(to: s.baseline.bounds); model = .spiking(s)
        }
    }
}
