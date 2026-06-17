import Foundation
import Testing
import CoreKit

@Suite("Seeded RNG determinism")
struct SeededRandomNumberGeneratorTests {

    @Test("Same seed produces an identical sequence")
    func sameSeedSameSequence() {
        var a = SeededRandomNumberGenerator(seed: 99)
        var b = SeededRandomNumberGenerator(seed: 99)
        let seqA = (0..<32).map { _ in a.next() }
        let seqB = (0..<32).map { _ in b.next() }
        #expect(seqA == seqB)
    }

    @Test("Different seeds diverge")
    func differentSeedsDiverge() {
        var a = SeededRandomNumberGenerator(seed: 1)
        var b = SeededRandomNumberGenerator(seed: 2)
        let seqA = (0..<32).map { _ in a.next() }
        let seqB = (0..<32).map { _ in b.next() }
        #expect(seqA != seqB)
    }

    @Test("Unit interval stays in [0, 1)")
    func unitIntervalBounds() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        for _ in 0..<1000 {
            let value = rng.nextUnitInterval()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("Gaussian samples average near the mean")
    func gaussianMean() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let n = 20_000
        let sum = (0..<n).reduce(into: 0.0) { acc, _ in acc += rng.nextGaussian(mean: 5, standardDeviation: 2) }
        let mean = sum / Double(n)
        #expect(abs(mean - 5) < 0.1)
    }

    @Test("nextUUID is deterministic for a given seed")
    func deterministicUUID() {
        var a = SeededRandomNumberGenerator(seed: 123)
        var b = SeededRandomNumberGenerator(seed: 123)
        #expect(a.nextUUID() == b.nextUUID())
    }
}
