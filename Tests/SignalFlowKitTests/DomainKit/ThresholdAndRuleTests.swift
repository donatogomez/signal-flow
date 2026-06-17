import Foundation
import Testing
import DomainKit

@Suite("Threshold & alert rule evaluation")
struct ThresholdAndRuleTests {

    struct BreachCase: Sendable, CustomTestStringConvertible {
        let lower: Double?
        let upper: Double?
        let value: Double
        let isBreached: Bool
        var testDescription: String { "lower=\(lower as Any) upper=\(upper as Any) value=\(value)" }
    }

    @Test("Threshold containment respects present bounds", arguments: [
        BreachCase(lower: nil, upper: 4, value: 3.9, isBreached: false),
        BreachCase(lower: nil, upper: 4, value: 4.0, isBreached: false), // inclusive
        BreachCase(lower: nil, upper: 4, value: 4.1, isBreached: true),
        BreachCase(lower: 2, upper: nil, value: 1.9, isBreached: true),
        BreachCase(lower: 2, upper: nil, value: 2.0, isBreached: false),
        BreachCase(lower: 2, upper: 8, value: 5.0, isBreached: false),
        BreachCase(lower: 2, upper: 8, value: 9.0, isBreached: true),
    ])
    func thresholdBreach(_ testCase: BreachCase) throws {
        let threshold = try Threshold(lowerBound: testCase.lower, upperBound: testCase.upper)
        #expect(threshold.isBreached(by: testCase.value) == testCase.isBreached)
    }

    @Test("Threshold requires at least one bound")
    func thresholdRequiresBound() {
        #expect(throws: ValidationError.self) { _ = try Threshold() }
    }

    @Test("Threshold rejects lower > upper")
    func thresholdRejectsInverted() {
        #expect(throws: ValidationError.self) { _ = try Threshold(lowerBound: 10, upperBound: 5) }
    }

    @Test("A breaching value raises an alert with the rule's severity")
    func ruleRaisesAlertOnBreach() throws {
        let deviceID = DeviceID()
        let rule = try Fixtures.temperatureRule(max: 4, severity: .critical)
        let breaching = try MeasuredValue(magnitude: 6.2, unit: .celsius)

        let alert = rule.evaluate(breaching, on: deviceID, at: Fixtures.referenceDate)

        let raised = try #require(alert)
        #expect(raised.severity == .critical)
        #expect(raised.deviceID == deviceID)
        #expect(raised.ruleID == rule.id)
        #expect(raised.observedValue == breaching)
        #expect(raised.isAcknowledged == false)
    }

    @Test("A value within range raises no alert")
    func ruleSilentWithinRange() throws {
        let rule = try Fixtures.temperatureRule(max: 4)
        let nominal = try MeasuredValue(magnitude: 3.0, unit: .celsius)
        #expect(rule.evaluate(nominal, on: DeviceID(), at: Fixtures.referenceDate) == nil)
    }

    @Test("A disabled rule never raises an alert")
    func disabledRuleSilent() throws {
        let rule = try Fixtures.temperatureRule(max: 4, enabled: false)
        let breaching = try MeasuredValue(magnitude: 99, unit: .celsius)
        #expect(rule.evaluate(breaching, on: DeviceID(), at: Fixtures.referenceDate) == nil)
    }
}
