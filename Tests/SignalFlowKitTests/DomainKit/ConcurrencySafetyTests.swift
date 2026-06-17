import Foundation
import Testing
import DomainKit

/// These tests don't just exercise behavior — that they *compile* under Swift 6 strict concurrency is
/// the assertion. Domain values are `Sendable`, so they cross actor and task boundaries freely.
@Suite("Concurrency safety")
struct ConcurrencySafetyTests {

    private actor AlertInbox {
        private var alerts: [Alert] = []
        func add(_ alert: Alert) { alerts.append(alert) } // Alert must be Sendable to arrive here
        var count: Int { alerts.count }
    }

    @Test("Domain values cross an actor boundary")
    func valuesCrossActorBoundary() async throws {
        let inbox = AlertInbox()
        let alert = Alert(
            deviceID: DeviceID(),
            ruleID: AlertRuleID(),
            metric: .temperature,
            severity: .warning,
            message: "warm",
            observedValue: try MeasuredValue(magnitude: 5, unit: .celsius),
            raisedAt: Fixtures.referenceDate
        )
        await inbox.add(alert)
        #expect(await inbox.count == 1)
    }

    @Test("Readings are processed concurrently in a task group")
    func readingsProcessConcurrently() async throws {
        let deviceID = DeviceID()
        let readings = try (0..<10).map {
            try Fixtures.temperatureReading(Double($0), deviceID: deviceID, at: TimeInterval($0))
        }

        let maximum = await withTaskGroup(of: Double.self) { group in
            for reading in readings {
                group.addTask { reading.value.magnitude } // reading captured across a task boundary
            }
            var result = -Double.infinity
            for await magnitude in group { result = max(result, magnitude) }
            return result
        }

        #expect(maximum == 9)
    }
}
