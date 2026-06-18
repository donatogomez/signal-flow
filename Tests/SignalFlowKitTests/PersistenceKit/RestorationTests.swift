import Foundation
import Testing
import DomainKit
import DataKit
import PersistenceKit

@Suite("Persistence restoration (end-to-end via DataKit)")
struct RestorationTests {

    @Test("A second launch restores the persisted fleet and latest telemetry")
    func restoresAcrossLaunches() async throws {
        let container = try PersistenceController.makeInMemoryContainer()

        // First "launch": ingest a bounded run and flush to persistence.
        let store1 = PersistenceStore(modelContainer: container)
        let source1 = SimulatedDataSource.persisted(seed: 7, maxTicks: 30, persistence: store1)
        try await source1.bootstrap()
        await source1.ingestAll()   // ingests + flushes buffered writes

        // Second "launch": a fresh data source over the same store restores state on bootstrap.
        let store2 = PersistenceStore(modelContainer: container)
        let source2 = SimulatedDataSource.persisted(seed: 7, maxTicks: 0, persistence: store2)
        try await source2.bootstrap()   // no ingestion — data must come from restore

        let assets = try await source2.assets.allAssets()
        #expect(assets.count == 10)

        let device = try #require(try await source2.devices.devices(inAsset: assets[0].id).first)
        let latest = try await source2.telemetry.latestReadings(forDevice: device.id)
        #expect(!latest.isEmpty)                      // restored latest telemetry
        #expect(device.connectivity.state == .online) // restored last-known connectivity
    }

    @Test("Persisted insight history survives a restore")
    func restoresInsightHistory() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let store = PersistenceStore(modelContainer: container)
        let deviceID = DeviceID()
        try await store.appendInsight(PX.insightRecord(device: deviceID, at: 100))

        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.insights.count == 1)
        #expect(snapshot.insights.first?.deviceID == deviceID)
    }
}
