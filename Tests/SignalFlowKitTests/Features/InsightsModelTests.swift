import Foundation
import Testing
import DomainKit
@testable import FeatureInsights

@MainActor
@Suite("Insights model")
struct InsightsModelTests {

    /// Builds a model over a single device whose temperature history is `temperatures`.
    private func makeModel(
        temperatures values: [Double],
        insight: DeviceInsight = .sample
    ) throws -> InsightsModel {
        let assetID = AssetID()
        let device = try FX.device("Reefer 12", asset: assetID, connectivity: .online)
        let history = try values.enumerated().map {
            try FX.reading(device: device.id, .temperature, $1, unit: .celsius, at: TimeInterval($0 * 60))
        }
        let assets = FakeAssetRepository(
            byID: [assetID: try FX.asset("Reefer 12", .refrigeratedTruck, id: assetID, devices: [device.id])],
            order: [assetID]
        )
        let devices = FakeDeviceRepository(byAsset: [assetID: [device]], byID: [device.id: device])
        let telemetry = FakeTelemetryRepository(history: [device.id: [.temperature: history]])
        return InsightsModel(
            assets: assets, devices: devices, telemetry: telemetry,
            alerts: FakeAlertRepository(), events: FakeEventRepository(),
            insights: FakeInsightsProvider(stub: insight)
        )
    }

    @Test("Loads the device picker and selects the first device")
    func loadsDevices() async throws {
        let model = try makeModel(temperatures: [])
        await model.loadDevices()
        #expect(model.devices.count == 1)
        #expect(model.selectedDeviceID == model.devices.first?.id)
    }

    @Test("Generates an insight when there is enough data, surfacing its source")
    func generatesInsight() async throws {
        let model = try makeModel(
            temperatures: [2, 4, 6],
            insight: DeviceInsight(summary: "s", anomalyExplanation: "a", recommendation: "r",
                                   severity: .watch, confidence: 0.7, source: .foundationModel)
        )
        await model.loadDevices()
        await model.generateInsight()
        #expect(model.phase == .ready)
        #expect(model.insight?.source == .foundationModel)
        #expect(model.insight?.severity == .watch)
    }

    @Test("Reports insufficient data when a device hasn't reported enough readings")
    func insufficientData() async throws {
        let model = try makeModel(temperatures: [5])
        await model.loadDevices()
        await model.generateInsight()
        #expect(model.phase == .insufficientData)
    }
}
