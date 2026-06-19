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

    @Test("A cleared alert is archived to history, not lost")
    func clearedAlertIsArchived() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12, at: 0)))
        #expect(await store.alertHistory(limit: 10).isEmpty)

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 4, at: 60)))
        let history = await store.alertHistory(limit: 10)
        #expect(history.count == 1)
        #expect(history.first?.severity == .critical)
        #expect(try await store.activeAlerts(forDevice: id).isEmpty)
    }

    @Test("History preserves whether a resolved alert had been acknowledged")
    func archivedAlertKeepsAcknowledgement() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12, at: 0)))
        let alert = try #require(try await store.activeAlerts(forDevice: id).first)
        try await store.acknowledgeAlert(alert.id, at: DataKitFixtures.origin.addingTimeInterval(30))

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 4, at: 60)))
        #expect(await store.alertHistory(limit: 10).first?.isAcknowledged == true)
    }

    @Test("Acknowledging an alert removes it from device health")
    func acknowledgeClearsDeviceHealth() async throws {
        let id = DeviceID()
        let store = try await storeWithTruckRule(id: id)
        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 12, at: 0)))

        let detail = FetchDeviceDetailUseCase(
            devices: StoreDeviceRepository(store: store),
            telemetry: StoreTelemetryRepository(store: store),
            alerts: StoreAlertRepository(store: store)
        )

        var result = try await detail(deviceID: id)
        #expect(result.status == .critical)
        let alert = try #require(result.activeAlerts.first)

        try await store.acknowledgeAlert(alert.id, at: DataKitFixtures.origin.addingTimeInterval(30))
        result = try await detail(deviceID: id)
        #expect(result.status != .critical)
    }
}
