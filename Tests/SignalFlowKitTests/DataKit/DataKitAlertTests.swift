import Foundation
import Testing
import DomainKit
import DataKit

@Suite("DataKit alert lifecycle")
struct DataKitAlertTests {

    private func storeWithTruckRule(id: DeviceID) async throws -> InMemoryTelemetryStore {
        let store = InMemoryTelemetryStore()
        await store.register([DataKitFixtures.entry(
            DataKitFixtures.descriptor(id: id),
            rules: [try DataKitFixtures.temperatureRule(max: 8)]
        )])
        return store
    }

    @Test("A breaching reading raises an alert with the rule's severity")
    func breachRaisesAlert() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)
        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12)))

        let alerts = try await store.activeAlerts(forDevice: id)
        #expect(alerts.count == 1)
        #expect(alerts.first?.severity == .critical)
        #expect(alerts.first?.metric == .temperature)
    }

    @Test("Repeated breaches do not duplicate the active alert")
    func breachesDeduplicate() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)
        for offset in 0..<5 {
            await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12, at: TimeInterval(offset * 60))))
        }
        #expect(try await store.activeAlerts(forDevice: id).count == 1)
    }

    @Test("Recovery within range clears the active alert")
    func recoveryClearsAlert() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)
        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12, at: 0)))
        #expect(try await store.activeAlerts(forDevice: id).count == 1)

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 4, at: 60)))
        #expect(try await store.activeAlerts(forDevice: id).isEmpty)
    }

    @Test("Acknowledging an alert marks it acknowledged")
    func acknowledge() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)
        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12)))
        let alert = try #require(try await store.activeAlerts(forDevice: id).first)

        try await store.acknowledgeAlert(alert.id, at: DataKitFixtures.origin.addingTimeInterval(120))
        #expect(try await store.activeAlerts(forDevice: id).first?.isAcknowledged == true)
    }

    @Test("Acknowledging an unknown alert throws")
    func acknowledgeUnknownThrows() async {
        let store = InMemoryTelemetryStore()
        await #expect(throws: DomainError.self) {
            try await store.acknowledgeAlert(AlertID(), at: DataKitFixtures.origin)
        }
    }
}
