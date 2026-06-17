import Foundation
import CoreKit

/// A bounded mean-reverting random walk (a discrete Ornstein–Uhlenbeck process).
///
/// Each step nudges the value a fraction `reversion` back toward `mean` and adds a small Gaussian
/// shock. The result wanders gradually and stays near its mean instead of jumping around — the core
/// trick behind realistic-feeling telemetry.
public struct MeanReverting: Sendable {
    public var value: Double
    public var mean: Double
    public var reversion: Double      // 0…1: pull toward the mean per step
    public var volatility: Double     // standard deviation of the per-step shock
    public var bounds: ClosedRange<Double>

    public init(value: Double, mean: Double, reversion: Double, volatility: Double, bounds: ClosedRange<Double>) {
        self.value = value
        self.mean = mean
        self.reversion = reversion
        self.volatility = volatility
        self.bounds = bounds
    }

    public mutating func advance(offset: Double, using rng: inout SeededRandomNumberGenerator) -> Double {
        let shock = rng.nextGaussian(standardDeviation: volatility)
        value += reversion * ((mean + offset) - value) + shock
        value = value.clamped(to: bounds)
        return value
    }
}

/// A day/night cycle (a sine wave over `periodSeconds`) plus a mean-reverting noise term.
///
/// Models temperature-like signals that follow a deterministic diurnal curve while still fluctuating
/// plausibly around it.
public struct Diurnal: Sendable {
    public var baseline: Double
    public var amplitude: Double
    public var periodSeconds: Double
    public var noise: MeanReverting
    public var bounds: ClosedRange<Double>

    public init(baseline: Double, amplitude: Double, periodSeconds: Double, noise: MeanReverting, bounds: ClosedRange<Double>) {
        self.baseline = baseline
        self.amplitude = amplitude
        self.periodSeconds = periodSeconds
        self.noise = noise
        self.bounds = bounds
    }

    public mutating func advance(sinceOrigin seconds: Double, offset: Double, using rng: inout SeededRandomNumberGenerator) -> Double {
        let phase = 2.0 * Double.pi * (seconds / periodSeconds)
        let cycle = baseline + amplitude * Foundation.sin(phase)
        let wobble = noise.advance(offset: 0, using: &rng)
        return (cycle + wobble + offset).clamped(to: bounds)
    }
}

/// A slow monotonic drift with small jitter, with optional recharge — models battery degradation.
///
/// When the value falls to `rechargeAt` it jumps back to `rechargeTo` (a battery swap/charge),
/// reported via the `recharged` flag so the device can emit an event.
public struct LinearDrift: Sendable {
    public var value: Double
    public var perStep: Double         // typically negative (discharge)
    public var jitter: Double
    public var bounds: ClosedRange<Double>
    public var rechargeAt: Double?
    public var rechargeTo: Double

    public init(value: Double, perStep: Double, jitter: Double, bounds: ClosedRange<Double>, rechargeAt: Double? = nil, rechargeTo: Double = 100) {
        self.value = value
        self.perStep = perStep
        self.jitter = jitter
        self.bounds = bounds
        self.rechargeAt = rechargeAt
        self.rechargeTo = rechargeTo
    }

    public mutating func advance(using rng: inout SeededRandomNumberGenerator) -> (value: Double, recharged: Bool) {
        var recharged = false
        value += perStep + rng.nextGaussian(standardDeviation: jitter)
        if let rechargeAt, value <= rechargeAt {
            value = rechargeTo
            recharged = true
        }
        value = value.clamped(to: bounds)
        return (value, recharged)
    }
}

/// A mean-reverting baseline with occasional decaying spikes — models CO₂ that drifts then jumps
/// when, say, a vent closes, before settling back down.
public struct Spiking: Sendable {
    public var baseline: MeanReverting
    public var spikeProbability: Double
    public var spikeMagnitude: ClosedRange<Double>
    public var decay: Double           // 0…1: residual fraction of the spike kept each step
    public var bounds: ClosedRange<Double>
    public var active: Double

    public init(baseline: MeanReverting, spikeProbability: Double, spikeMagnitude: ClosedRange<Double>, decay: Double, bounds: ClosedRange<Double>, active: Double = 0) {
        self.baseline = baseline
        self.spikeProbability = spikeProbability
        self.spikeMagnitude = spikeMagnitude
        self.decay = decay
        self.bounds = bounds
        self.active = active
    }

    public mutating func advance(using rng: inout SeededRandomNumberGenerator) -> Double {
        let base = baseline.advance(offset: 0, using: &rng)
        if active < 1, rng.chance(spikeProbability) {
            active = rng.nextDoubleInRange(spikeMagnitude)
        }
        let value = (base + active).clamped(to: bounds)
        active *= decay
        if active < 1 { active = 0 }
        return value
    }
}

extension SeededRandomNumberGenerator {
    /// Convenience uniform double in a closed range.
    mutating func nextDoubleInRange(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnitInterval() * (range.upperBound - range.lowerBound)
    }
}
