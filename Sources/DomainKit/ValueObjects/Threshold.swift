/// An inclusive acceptable range for a metric, expressed as optional lower and/or upper bounds.
///
/// A value is *within* the threshold when it satisfies every present bound; otherwise it is a
/// *breach*. Construction enforces that at least one bound exists, that bounds are finite, and that
/// a lower bound never exceeds an upper bound — so a `Threshold` is always meaningful to evaluate.
public struct Threshold: Hashable, Sendable {
    public let lowerBound: Double?
    public let upperBound: Double?

    public init(lowerBound: Double? = nil, upperBound: Double? = nil) throws {
        if let lowerBound, !lowerBound.isFinite {
            throw ValidationError.invalidThreshold(reason: "lower bound is not finite")
        }
        if let upperBound, !upperBound.isFinite {
            throw ValidationError.invalidThreshold(reason: "upper bound is not finite")
        }
        guard lowerBound != nil || upperBound != nil else {
            throw ValidationError.invalidThreshold(reason: "a threshold needs at least one bound")
        }
        if let lowerBound, let upperBound, lowerBound > upperBound {
            throw ValidationError.invalidThreshold(
                reason: "lower bound \(lowerBound) exceeds upper bound \(upperBound)"
            )
        }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public func contains(_ value: Double) -> Bool {
        if let lowerBound, value < lowerBound { return false }
        if let upperBound, value > upperBound { return false }
        return true
    }

    public func isBreached(by value: Double) -> Bool { !contains(value) }
}

extension Threshold: CustomStringConvertible {
    public var description: String {
        switch (lowerBound, upperBound) {
        case let (lower?, upper?): "\(lower)…\(upper)"
        case let (lower?, nil): "≥ \(lower)"
        case let (nil, upper?): "≤ \(upper)"
        case (nil, nil): "" // unreachable: construction guarantees at least one bound
        }
    }
}

extension Threshold: Codable {
    private enum CodingKeys: String, CodingKey { case lowerBound, upperBound }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lowerBound: container.decodeIfPresent(Double.self, forKey: .lowerBound),
            upperBound: container.decodeIfPresent(Double.self, forKey: .upperBound)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lowerBound, forKey: .lowerBound)
        try container.encodeIfPresent(upperBound, forKey: .upperBound)
    }
}
