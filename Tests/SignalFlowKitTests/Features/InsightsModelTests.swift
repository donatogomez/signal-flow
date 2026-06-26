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

    @Test("Builds a feed item per device with enough data, adapting the insight")
    func buildsFeed() async throws {
        let model = try makeModel(
            temperatures: [2, 4, 6],
            insight: DeviceInsight(summary: "s", anomalyExplanation: "a", recommendation: "r",
                                   severity: .watch, confidence: 0.7, source: .foundationModel)
        )
        await model.load()

        #expect(model.phase == .ready)
        #expect(model.items.count == 1)
        let item = try #require(model.items.first)
        #expect(item.deviceName == "Reefer 12")
        #expect(item.metric == .temperature)
        #expect(item.observation == "s")
        #expect(item.recommendation == "r")
        #expect(item.severity == .watch)
        #expect(item.source == .foundationModel)
    }

    @Test("Empty feed when no device has enough data")
    func emptyFeed() async throws {
        let model = try makeModel(temperatures: [5]) // below the minimum for statistics
        await model.load()
        #expect(model.phase == .empty)
        #expect(model.items.isEmpty)
    }
}
