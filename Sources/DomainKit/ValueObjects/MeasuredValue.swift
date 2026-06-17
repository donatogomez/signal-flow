/// A single, unit-aware measurement.
///
/// Construction is validating: a non-finite magnitude (`NaN`/`±∞`) is rejected, so a `MeasuredValue`
/// is guaranteed to hold a usable number. The validating initializer is also used on `Codable`
/// decode, so the invariant survives serialization.
public struct MeasuredValue: Hashable, Sendable {
    public let magnitude: Double
    public let unit: MeasurementUnit

    public init(magnitude: Double, unit: MeasurementUnit) throws {
        guard magnitude.isFinite else { throw ValidationError.nonFiniteMeasurement(magnitude) }
        self.magnitude = magnitude
        self.unit = unit
    }
}

extension MeasuredValue: CustomStringConvertible {
    public var description: String {
        unit.symbol.isEmpty ? "\(magnitude)" : "\(magnitude) \(unit.symbol)"
    }
}

extension MeasuredValue: Codable {
    private enum CodingKeys: String, CodingKey { case magnitude, unit }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            magnitude: container.decode(Double.self, forKey: .magnitude),
            unit: container.decode(MeasurementUnit.self, forKey: .unit)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(magnitude, forKey: .magnitude)
        try container.encode(unit, forKey: .unit)
    }
}
