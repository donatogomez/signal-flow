import Foundation
import Testing
import DomainKit
import DataKit
@testable import FeatureFleet

@MainActor
@Suite("Fleet model")
struct FleetModelTests {

    /// Three devices across three assets: one nominal (greenhouse, online), one critical (truck,
    /// online + a critical alert), one offline (warehouse).
    private func craftedModel() throws -> FleetModel {
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
        return FleetModel(assets: assets, devices: devices, alerts: alerts)
    }

    @Test("Loads one row per device")
    func loadsRows() async throws {
        let model = try craftedModel()
        await model.refresh()
        #expect(model.phase == .loaded)
        #expect(model.rows.count == 3)
    }

    @Test("Search matches device or asset name")
    func search() async throws {
        let model = try craftedModel()
        await model.refresh()
        model.searchText = "Greenhouse"
        #expect(model.visibleRows.count == 1)
        #expect(model.visibleRows.first?.assetName == "Greenhouse A")
    }

    @Test("Status filter narrows to one status")
    func statusFilter() async throws {
        let model = try craftedModel()
        await model.refresh()
        model.statusFilter = .critical
        #expect(model.visibleRows.count == 1)
        #expect(model.visibleRows.allSatisfy { $0.status == .critical })
    }

    @Test("Sorting by status surfaces critical first")
    func sortByStatus() async throws {
        let model = try craftedModel()
        await model.refresh()
        model.sort = .status
        #expect(model.visibleRows.first?.status == .critical)
    }

    @Test("Sorting by name is alphabetical")
    func sortByName() async throws {
        let model = try craftedModel()
        await model.refresh()
        model.sort = .name
        let names = model.visibleRows.map(\.deviceName)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test("Integration: loads the full simulated fleet through DataKit")
    func integrationWithDataKit() async throws {
        let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: 20)
        try await source.bootstrap()
        await source.ingestAll()
        let model = FleetModel(assets: source.assets, devices: source.devices, alerts: source.alerts)
        await model.refresh()
        #expect(model.phase == .loaded)
        #expect(model.rows.count == 10)
    }
}
