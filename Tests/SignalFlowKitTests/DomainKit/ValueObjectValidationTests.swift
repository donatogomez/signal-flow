import Foundation
import Testing
import DomainKit

@Suite("Value object validation")
struct ValueObjectValidationTests {

    // MARK: MeasuredValue

    @Test("MeasuredValue accepts a finite magnitude")
    func measuredValueAcceptsFinite() throws {
        let value = try MeasuredValue(magnitude: 3.5, unit: .celsius)
        #expect(value.magnitude == 3.5)
        #expect(value.unit == .celsius)
    }

    @Test("MeasuredValue rejects non-finite magnitudes", arguments: [Double.nan, .infinity, -.infinity])
    func measuredValueRejectsNonFinite(_ magnitude: Double) {
        #expect(throws: ValidationError.self) {
            _ = try MeasuredValue(magnitude: magnitude, unit: .celsius)
        }
    }

    // MARK: BatteryStatus

    @Test("BatteryStatus accepts 0…100", arguments: [0.0, 12.0, 100.0])
    func batteryAcceptsValid(_ percentage: Double) throws {
        let battery = try BatteryStatus(percentage: percentage)
        #expect(battery.percentage == percentage)
    }

    @Test("BatteryStatus rejects impossible percentages", arguments: [-0.1, 100.1, 250.0])
    func batteryRejectsImpossible(_ percentage: Double) {
        #expect(throws: ValidationError.self) {
            _ = try BatteryStatus(percentage: percentage)
        }
    }

    @Test("BatteryStatus level reflects charge")
    func batteryLevel() throws {
        #expect(try BatteryStatus(percentage: 5).level == .critical)
        #expect(try BatteryStatus(percentage: 20).level == .low)
        #expect(try BatteryStatus(percentage: 80).level == .nominal)
    }

    // MARK: Location

    @Test("Location accepts on-Earth coordinates")
    func locationAcceptsValid() throws {
        let location = try Location(latitude: 41.4, longitude: 2.1, altitude: 12)
        #expect(location.latitude == 41.4)
    }

    @Test("Location rejects off-Earth coordinates")
    func locationRejectsInvalid() {
        #expect(throws: ValidationError.self) { _ = try Location(latitude: 91, longitude: 0) }
        #expect(throws: ValidationError.self) { _ = try Location(latitude: 0, longitude: 181) }
    }

    // MARK: TimeRange

    @Test("TimeRange accepts start <= end and reports duration")
    func timeRangeValid() throws {
        let start = Fixtures.referenceDate
        let range = try TimeRange(start: start, end: start.addingTimeInterval(3600))
        #expect(range.duration == 3600)
        #expect(range.contains(start.addingTimeInterval(1800)))
    }

    @Test("TimeRange rejects an inverted range")
    func timeRangeRejectsInverted() {
        let start = Fixtures.referenceDate
        #expect(throws: ValidationError.self) {
            _ = try TimeRange(start: start, end: start.addingTimeInterval(-1))
        }
    }

    // MARK: MetricDefinition

    @Test("MetricDefinition rejects an empty name")
    func metricDefinitionRejectsEmptyName() {
        #expect(throws: ValidationError.self) {
            _ = try MetricDefinition(kind: .temperature, name: "   ")
        }
    }

    @Test("MetricDefinition validates a reading's unit and range")
    func metricDefinitionValidatesReadings() throws {
        let definition = try MetricDefinition(
            kind: .temperature,
            name: "Internal temp",
            unit: .celsius,
            validRange: -30...30
        )
        try definition.validate(try MeasuredValue(magnitude: 4, unit: .celsius)) // does not throw
        #expect(throws: ValidationError.self) {
            try definition.validate(try MeasuredValue(magnitude: 4, unit: .percent)) // unit mismatch
        }
        #expect(throws: ValidationError.self) {
            try definition.validate(try MeasuredValue(magnitude: 99, unit: .celsius)) // out of range
        }
    }
}
