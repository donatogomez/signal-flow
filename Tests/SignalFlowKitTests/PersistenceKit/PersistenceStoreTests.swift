import Foundation
import Testing
import DomainKit
import PersistenceKit

@Suite("Persistence store (ModelActor)")
struct PersistenceStoreTests {

    private func makeStore() throws -> PersistenceStore {
        PersistenceStore(modelContainer: try PersistenceController.makeInMemoryContainer())
    }

    @Test("Round-trip: written entities come back through loadSnapshot")
    func roundTrip() async throws {
        let store = try makeStore()
        let assetID = AssetID()
        let deviceID = DeviceID()
        let asset = try PX.asset(id: assetID, devices: [deviceID])
        let device = try PX.device(id: deviceID, asset: assetID)

        try await store.upsertCatalog(assets: [asset], devices: [device])
        try await store.appendReadings([
            try PX.reading(device: deviceID, .temperature, 3, at: 0),
            try PX.reading(device: deviceID, .temperature, 5, at: 60),
        ])
        try await store.appendEvents([PX.event(device: deviceID, at: 30)])
        try await store.replaceActiveAlerts([try PX.alert(device: deviceID)], forDevice: deviceID)
        try await store.appendInsight(PX.insightRecord(device: deviceID))

        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.assets.count == 1)
        #expect(snapshot.devices.count == 1)
        #expect(snapshot.latestReadings.first(where: { $0.metric == .temperature })?.value.magnitude == 5) // latest
        #expect(snapshot.events.count == 1)
        #expect(snapshot.alerts.count == 1)
        #expect(snapshot.insights.count == 1)
    }

    @Test("Re-appending the same reading id is idempotent")
    func idempotentAppend() async throws {
        let store = try makeStore()
        let deviceID = DeviceID()
        let id = ReadingID()
        let reading = try PX.reading(device: deviceID, .temperature, 3, at: 0, id: id)

        try await store.appendReadings([reading])
        try await store.appendReadings([reading]) // same id — upsert, not a duplicate
        #expect(try await store.readingCount() == 1)
    }

    @Test("Concurrent appends are serialized by the actor with no loss")
    func actorIsolation() async throws {
        let store = try makeStore()
        let deviceID = DeviceID()
        let readings = try (0..<200).map { try PX.reading(device: deviceID, .temperature, Double($0), at: TimeInterval($0)) }

        await withTaskGroup(of: Void.self) { group in
            for reading in readings {
                group.addTask { try? await store.appendReadings([reading]) }
            }
        }
        #expect(try await store.readingCount() == 200)
    }

    @Test("Retention caps the number of readings kept per series")
    func retention() async throws {
        let store = try makeStore()
        await store.setRetention(RetentionPolicy(maxReadingsPerSeries: 10))
        let deviceID = DeviceID()
        let readings = try (0..<25).map { try PX.reading(device: deviceID, .temperature, Double($0), at: TimeInterval($0)) }

        try await store.appendReadings(readings)
        #expect(try await store.readingCount() == 10)

        // The 10 kept are the most recent.
        let latest = try await store.loadSnapshot().latestReadings.first { $0.metric == .temperature }
        #expect(latest?.value.magnitude == 24)
    }
}
