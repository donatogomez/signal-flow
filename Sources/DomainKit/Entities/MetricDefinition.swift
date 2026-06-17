/// The specification of a metric a device can report: its semantic kind, display name, unit, and an
/// optional plausible range used to validate incoming readings.
public struct MetricDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: MetricID
    public let kind: MetricKind
    public let name: String
    public let unit: MeasurementUnit
    public let validRange: ClosedRange<Double>?

    public init(
        id: MetricID = MetricID(),
        kind: MetricKind,
        name: String,
        unit: MeasurementUnit? = nil,
        validRange: ClosedRange<Double>? = nil
    ) throws {
        self.id = id
        self.kind = kind
        self.name = try DomainText.validatedName(name, context: "MetricDefinition")
        self.unit = unit ?? kind.canonicalUnit
        self.validRange = validRange
    }

    /// Validates a measured value against this definition's unit and plausible range.
    public func validate(_ value: MeasuredValue) throws {
        guard value.unit == unit else {
            throw ValidationError.unitMismatch(expected: unit, actual: value.unit)
        }
        if let validRange, !validRange.contains(value.magnitude) {
            throw ValidationError.valueOutOfRange(value: value.magnitude, range: validRange)
        }
    }
}
