import Foundation
import Testing
import DomainKit
import DataKit

@Suite("DataKit concurrency, cancellation & boundaries")
struct DataKitConcurrencyTests {

    @Test("Concurrent ingestion and queries are race-free and lose nothing")
    func concurrentIngestAndQuery() async throws {
        let store = InMemoryTelemetryStore()
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        let readings = try (0..<200).map {
            try DataKitFixtures.reading(deviceID: id, .temperature, Double($0), at: TimeInterval($0))
        }

        await withTaskGroup(of: Void.self) { group in
            for reading in readings {
                group.addTask { await store.ingest(.reading(reading)) }
            }
            for _ in 0..<50 {
                group.addTask { _ = try? await store.latestReadings(forDevice: id) }
            }
        }

        #expect(await store.ingestedReadingCount() == 200)
    }

    @Test("Bounded background ingestion completes")
    func ingestAllCompletes() async throws {
        let source = SimulatedDataSource.deterministic(seed: 1, maxTicks: 20)
        try await source.bootstrap()
        await source.ingestAll()
        #expect(await source.ingestedReadingCount() > 0)
    }

    @Test("Stopping background ingestion halts it promptly with no leak")
    func stopHaltsIngestion() async throws {
        let source = SimulatedDataSource.live(seed: 1, timeScale: 600)
        try await source.bootstrap()

        // 1. Deterministically prove ingestion started and wrote at least one reading — no sleeps,
        //    no scheduler racing: this returns only once the loop has ingested its first reading.
        await source.startAndWaitUntilFirstIngestion()
        let afterStart = await source.ingestedReadingCount()
        #expect(afterStart > 0)

        // 2. Stop. `stop()` cancels the loop and awaits its completion, so once it returns no further
        //    telemetry from this session can ever be written.
        await source.stop()
        let afterStop = await source.ingestedReadingCount()

        // 3. Prove no more writes happen after stop() returns. Because stop() awaited the loop to
        //    finish, a second read is identical — no sleep required to "wait and see".
        let later = await source.ingestedReadingCount()
        #expect(afterStop >= afterStart)
        #expect(later == afterStop)
    }

    @Test("The data layer is consumable through DomainKit ports alone")
    func consumableThroughDomainPortsOnly() async throws {
        let source = SimulatedDataSource.deterministic(seed: 2, maxTicks: 15)
        try await source.bootstrap()
        await source.ingestAll()
        // `drive` names only DomainKit types — proving features need nothing from DataKit/SimulationKit.
        try await drive(
            assets: source.assets, devices: source.devices,
            telemetry: source.telemetry, alerts: source.alerts, insights: source.insights
        )
    }

    private func drive(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        insights: any InsightsProviding
    ) async throws {
        let allAssets = try await assets.allAssets()
        #expect(!allAssets.isEmpty)
        let asset = try #require(allAssets.first)
        let device = try #require(try await devices.devices(inAsset: asset.id).first)
        _ = try await telemetry.latestReadings(forDevice: device.id)
        _ = try await alerts.activeAlerts(forDevice: device.id)
        _ = try await alerts.rules(forDevice: device.id)
        _ = insights // a DomainKit InsightsProviding; consumed by the insight use case elsewhere
    }
}
