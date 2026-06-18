import Foundation
import Testing
import DomainKit
import DataKit

@Suite("Simulated data source ↔ domain use cases")
struct SimulatedDataSourceTests {

    private func preparedSource(maxTicks: Int = 40) async throws -> SimulatedDataSource {
        let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: maxTicks)
        try await source.bootstrap()
        await source.ingestAll()
        return source
    }

    @Test("FetchFleetOverview returns all ten assets with derived device status")
    func fleetOverview() async throws {
        let source = try await preparedSource()
        let overview = FetchFleetOverviewUseCase(assets: source.assets, devices: source.devices, alerts: source.alerts)
        let fleet = try await overview()

        #expect(fleet.count == 10)
        #expect(fleet.allSatisfy { !$0.devices.isEmpty })
        // After ingestion at least one device should have reported in (i.e. not all offline).
        let statuses = fleet.flatMap { $0.devices.map(\.status) }
        #expect(statuses.contains { $0 != .offline })
    }

    @Test("FetchDeviceDetail returns latest readings for a device")
    func deviceDetail() async throws {
        let source = try await preparedSource()
        let asset = try #require(try await source.assets.allAssets().first)
        let device = try #require(try await source.devices.devices(inAsset: asset.id).first)

        let detail = try await FetchDeviceDetailUseCase(
            devices: source.devices, telemetry: source.telemetry, alerts: source.alerts
        )(deviceID: device.id)

        #expect(detail.device.id == device.id)
        #expect(!detail.latestReadings.isEmpty)
    }

    @Test("FetchTelemetryHistory returns ordered history for a device's metric")
    func telemetryHistory() async throws {
        let source = try await preparedSource()
        let asset = try #require(try await source.assets.allAssets().first)
        let device = try #require(try await source.devices.devices(inAsset: asset.id).first)

        let history = try await FetchTelemetryHistoryUseCase(telemetry: source.telemetry)(
            deviceID: device.id, metric: .temperature, range: try DataKitFixtures.wideRange()
        )

        #expect(history.count > 1)
        #expect(history == history.sorted { $0.recordedAt < $1.recordedAt })
    }

    @Test("The same seed yields the same number of ingested readings")
    func deterministicVolume() async throws {
        let a = try await preparedSource(maxTicks: 25)
        let b = try await preparedSource(maxTicks: 25)
        let countA = await a.ingestedReadingCount()
        let countB = await b.ingestedReadingCount()
        #expect(countA == countB)
        #expect(countA > 0)
    }
}
