import Foundation
import Testing
import DomainKit
import DataKit

@Suite("In-memory telemetry store")
struct InMemoryTelemetryStoreTests {

    @Test("Registering a catalog makes assets and devices queryable before any telemetry")
    func registerCatalog() async throws {
        let store = InMemoryTelemetryStore()
        let deviceID = DeviceID()
        let assetID = AssetID()
        await store.register([DataKitFixtures.entry(
            DataKitFixtures.descriptor(id: deviceID, assetID: assetID, name: "Reefer 12")
        )])

        let assets = try await store.allAssets()
        #expect(assets.count == 1)
        #expect(assets.first?.id == assetID)
        #expect(assets.first?.deviceIDs == [deviceID])

        let device = try await store.device(deviceID)
        #expect(device.name == "Reefer 12")
        #expect(device.connectivity.state == .offline) // no telemetry yet
        #expect(device.metrics.isEmpty)
    }

    @Test("Ingesting readings updates the latest snapshot and history, and marks the device online")
    func ingestReadings() async throws {
        let store = InMemoryTelemetryStore()
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 3, at: 0)))
        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 5, at: 60)))

        let latest = try await store.latestReadings(forDevice: id)
        #expect(latest.first(where: { $0.metric == .temperature })?.value.magnitude == 5)

        let device = try await store.device(id)
        #expect(device.connectivity.state == .online)
        #expect(device.metrics.contains { $0.kind == .temperature })

        let history = try await store.readings(forDevice: id, metric: .temperature, in: try DataKitFixtures.wideRange())
        #expect(history.map(\.value.magnitude) == [3, 5])   // ordered oldest-first
    }

    @Test("A disconnect event takes the device offline; a connect brings it back")
    func connectivityEvents() async throws {
        let store = InMemoryTelemetryStore()
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 3)))
        #expect(try await store.device(id).connectivity.state == .online)

        await store.ingest(.event(DataKitFixtures.event(deviceID: id, .disconnected, at: 60)))
        #expect(try await store.device(id).connectivity.state == .offline)

        await store.ingest(.event(DataKitFixtures.event(deviceID: id, .connected, at: 120)))
        #expect(try await store.device(id).connectivity.state == .online)
    }

    @Test("A location update populates the device's last-known location")
    func locationUpdate() async throws {
        let store = InMemoryTelemetryStore()
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        let location = try Location(latitude: 41.4, longitude: 2.1)
        await store.ingest(.location(deviceID: id, location: location, recordedAt: DataKitFixtures.origin))
        #expect(try await store.device(id).lastKnownLocation == location)
    }

    @Test("Querying an unknown device throws deviceNotFound")
    func unknownDeviceThrows() async {
        let store = InMemoryTelemetryStore()
        await #expect(throws: DomainError.self) { _ = try await store.device(DeviceID()) }
    }
}
