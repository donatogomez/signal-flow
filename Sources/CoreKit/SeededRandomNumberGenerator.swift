import Foundation

/// A deterministic, `Sendable` pseudo-random number generator (SplitMix64).
///
/// Determinism is the whole point: given the same `seed`, the sequence is identical on every run and
/// every machine, which is what makes the simulation reproducible and its tests free of flakiness.
/// It conforms to `RandomNumberGenerator`, so the standard `Int.random(in:using:)` family works too.
///
/// Being a value type, each owner (e.g. each simulated device) holds its *own* generator state — there
/// is no shared mutable RNG to coordinate across actors.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public extension SeededRandomNumberGenerator {
    /// A uniform double in `[0, 1)` with full 53-bit resolution.
    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A normally distributed double (Box–Muller). Used to make telemetry drift gradually rather than
    /// jump around — small Gaussian shocks accumulate into plausible signals.
    mutating func nextGaussian(mean: Double = 0, standardDeviation: Double = 1) -> Double {
        let u1 = Swift.max(nextUnitInterval(), .leastNonzeroMagnitude)
        let u2 = nextUnitInterval()
        let magnitude = (-2.0 * Foundation.log(u1)).squareRoot()
        return mean + standardDeviation * magnitude * Foundation.cos(2.0 * .pi * u2)
    }

    /// Returns `true` with the given probability in `0...1`.
    mutating func chance(_ probability: Double) -> Bool {
        nextUnitInterval() < probability
    }

    /// A deterministic `UUID` derived from the generator, so simulated entities have stable identity
    /// across runs (essential for asserting `Equatable` telemetry in tests).
    mutating func nextUUID() -> UUID {
        let hi = next()
        let lo = next()
        func byte(_ value: UInt64, _ index: UInt64) -> UInt8 { UInt8((value >> (8 * index)) & 0xFF) }
        return UUID(uuid: (
            byte(hi, 0), byte(hi, 1), byte(hi, 2), byte(hi, 3),
            byte(hi, 4), byte(hi, 5), byte(hi, 6), byte(hi, 7),
            byte(lo, 0), byte(lo, 1), byte(lo, 2), byte(lo, 3),
            byte(lo, 4), byte(lo, 5), byte(lo, 6), byte(lo, 7)
        ))
    }
}
