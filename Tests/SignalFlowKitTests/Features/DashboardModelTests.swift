import Foundation
import Testing
import DomainKit
import DataKit
@testable import FeatureDashboard

@MainActor
@Suite("Dashboard model")
struct DashboardModelTests {

    @Test("Aggregates fleet stats and resolves event device names")
    func aggregates() async throws {
        let ghAsset = AssetID(), rfAsset = AssetID(), whAsset = AssetID()
        let gh = try FX.device("GH Sensor", asset: ghAsset, connectivity: .online)
        let rf = try FX.device("Reefer 12", asset: rfAsset, connectivity: .online)
        let wh = try FX.device("WH Sensor", asset: whAsset, connectivity: .offline)

        let assets = FakeAssetRepository(
            byID: [
                ghAsset: try FX.asset("Greenhouse A", .greenhouse, id: ghAsset, devices: [gh.id]),
                rfAsset: try FX.asset("Reefer 12", .refrigeratedTruck, id: rfAsset, devices: [rf.id]),
                whAsset: try FX.asset("Warehouse", .warehouse, id: whAsset, devices: [wh.id]),
            ],
            order: [ghAsset, rfAsset, whAsset]
        )
        let devices = FakeDeviceRepository(
            byAsset: [ghAsset: [gh], rfAsset: [rf], whAsset: [wh]],
            byID: [gh.id: gh, rf.id: rf, wh.id: wh]
        )
        let alerts = FakeAlertRepository(alertsByDevice: [rf.id: [try FX.criticalAlert(device: rf.id)]])
        let events = FakeEventRepository(events: [FX.event(device: rf.id, .disconnected, at: 5)])

        let model = DashboardModel(assets: assets, devices: devices, alerts: alerts, events: events)
        await model.refresh()

        #expect(model.phase == .loaded)
        #expect(model.stats.totalDevices == 3)
        #expect(model.stats.online == 2)
        #expect(model.stats.offline == 1)
        #expect(model.stats.assetCount == 3)
        #expect(model.stats.critical == 1)
        #expect(model.stats.nominal == 1)
        #expect(model.stats.activeAlerts == 1)
        #expect(model.recentEvents.count == 1)
        #expect(model.recentEvents.first?.deviceName == "Reefer 12")
    }

    @Test("Integration: aggregates the full simulated fleet through DataKit")
    func integrationWithDataKit() async throws {
        let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: 25)
        try await source.bootstrap()
        await source.ingestAll()
        let model = DashboardModel(assets: source.assets, devices: source.devices, alerts: source.alerts, events: source.events)
        await model.refresh()
        #expect(model.phase == .loaded)
        #expect(model.stats.totalDevices == 10)
        #expect(model.stats.online + model.stats.offline == 10)
    }

    @Test("Health fraction and band derive from the nominal share")
    func healthScore() {
        var stats = FleetStats()
        stats.totalDevices = 10
        stats.nominal = 8
        #expect(abs(stats.healthFraction - 0.8) < 0.0001)
        #expect(stats.healthBand == .excellent)

        stats.nominal = 5 // 50%
        #expect(stats.healthBand == .attention)

        // Empty fleet: no devices ⇒ no score, no false-green band.
        let empty = FleetStats()
        #expect(empty.healthFraction == 0)
        #expect(empty.healthBand == .unknown)
    }
}
