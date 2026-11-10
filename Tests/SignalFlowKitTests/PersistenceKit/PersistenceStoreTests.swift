import Foundation
import Testing
import DomainKit
@testable import PersistenceKit

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

    @Test("Restore returns exactly the newest reading of every device/metric series")
    func latestReadingPerSeries() async throws {
        let store = try makeStore()
        let devices = [DeviceID(), DeviceID(), DeviceID()]
        // Out-of-order timestamps, so "newest" can't come from insertion order.
        let offsets: [TimeInterval] = [40, 10, 90, 20, 70]
        var readings: [TelemetryReading] = []
        for (index, device) in devices.enumerated() {
            for offset in offsets {
                readings.append(try PX.reading(device: device, .temperature, offset, at: offset + Double(index)))
                readings.append(try PX.reading(device: device, .humidity, offset, unit: .percent, at: offset + Double(index)))
            }
        }
        try await store.appendReadings(readings)

        let latest = try await store.loadSnapshot().latestReadings
        #expect(latest.count == devices.count * 2)
        #expect(Set(latest.map { "\($0.deviceID)|\($0.metric)" }).count == latest.count)
        #expect(latest.allSatisfy { $0.value.magnitude == 90 })
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

    /// The coordinator re-sends a whole batch after a failed append (docs/21 §21.4). If part of it was
    /// already committed, the retry must not duplicate those rows: `id` is `@Attribute(.unique)` and
    /// each append checks for the id first.
    @Test("Re-sending a batch after part of it was committed stores each item once")
    func retryAfterPartialCommit() async throws {
        let store = try makeStore()
        let deviceID = DeviceID()
        let readings = try (0..<10).map { try PX.reading(device: deviceID, .temperature, Double($0), at: TimeInterval($0)) }
        let events = (0..<4).map { PX.event(device: deviceID, at: TimeInterval($0)) }

        try await store.appendReadings(Array(readings.prefix(4)))   // the part that made it
        try await store.appendEvents(Array(events.prefix(1)))
        try await store.appendReadings(readings)                    // the retry
        try await store.appendEvents(events)
        try await store.appendReadings(readings)                    // and a second one

        #expect(try await store.readingCount() == readings.count)
        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.events.count == events.count)
        #expect(Set(snapshot.events.map(\.id)) == Set(events.map(\.id)))
    }

    /// A failed save must not leave its changes pending: they would grow with every failing flush and
    /// be committed by the next successful save, even ones the coordinator had already dropped.
    @Test("A failed save leaves nothing pending in the context")
    func failedSaveIsDiscarded() async throws {
        let store = try makeStore()
        let deviceID = DeviceID()
        let failed = try (0..<10).map { try PX.reading(device: deviceID, .temperature, Double($0), at: TimeInterval($0)) }
        let later = try (10..<13).map { try PX.reading(device: deviceID, .temperature, Double($0), at: TimeInterval($0)) }

        await store.failSaves(with: CocoaError(.fileWriteOutOfSpace))
        await #expect(throws: CocoaError.self) { try await store.appendReadings(failed) }
        await #expect(throws: CocoaError.self) { try await store.appendEvents([PX.event(device: deviceID, at: 0)]) }
        await store.failSaves(with: nil)

        try await store.appendReadings(later)
        #expect(try await store.readingCount() == later.count)     // the failed batch wasn't committed with it
        #expect(try await store.loadSnapshot().events.isEmpty)

        try await store.appendReadings(failed)                     // the caller's retry still stores it
        #expect(try await store.readingCount() == failed.count + later.count)
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
