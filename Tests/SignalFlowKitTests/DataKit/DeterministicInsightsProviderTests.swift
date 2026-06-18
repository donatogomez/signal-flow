import Foundation
import Testing
import DomainKit
import DataKit

@Suite("Deterministic insights provider")
struct DeterministicInsightsProviderTests {

    private let provider = DeterministicInsightsProvider()

    private func context(trend: TrendDirection, activeAlerts: Int = 0, sampleCount: Int = 20) throws -> InsightContext {
        let stats = InsightStatistics(
            metric: .temperature, unit: .celsius, latest: 4, minimum: 2, maximum: 6,
            average: 4, trend: trend, sampleCount: sampleCount
        )
        return InsightContext(
            deviceName: "Reefer 12", assetKind: .refrigeratedTruck, statistics: stats,
            activeAlertCount: activeAlerts, recentEventCount: 3, range: try DataKitFixtures.wideRange()
        )
    }

    @Test("Produces an insight tagged as deterministic, grounded in the context")
    func deterministicSource() async throws {
        let insight = try await provider.insight(for: try context(trend: .stable))
        #expect(insight.source == .deterministic)
        #expect(insight.summary.contains("Reefer 12"))
        #expect(insight.summary.contains("Temperature"))
        #expect(!insight.recommendation.isEmpty)
        #expect((0...1).contains(insight.confidence))
    }

    @Test("Active alerts raise the advisory severity to concern")
    func alertsConcern() async throws {
        let insight = try await provider.insight(for: try context(trend: .stable, activeAlerts: 2))
        #expect(insight.severity == .concern)
        #expect(insight.anomalyExplanation.localizedCaseInsensitiveContains("alert"))
    }

    @Test("A volatile trend is a watch; calm, alert-free telemetry is nominal")
    func severityFromTrend() async throws {
        #expect(try await provider.insight(for: try context(trend: .volatile)).severity == .watch)
        #expect(try await provider.insight(for: try context(trend: .stable)).severity == .nominal)
    }

    @Test("Reachable end-to-end through GenerateDeviceInsight on the simulated source")
    func viaUseCase() async throws {
        let source = SimulatedDataSource.deterministic(seed: 3, maxTicks: 40)
        try await source.bootstrap()
        await source.ingestAll()
        let asset = try #require(try await source.assets.allAssets().first)
        let device = try #require(try await source.devices.devices(inAsset: asset.id).first)

        let insight = try await GenerateDeviceInsightUseCase(
            devices: source.devices, assets: source.assets, telemetry: source.telemetry,
            alerts: source.alerts, events: source.events, insights: source.insights
        )(deviceID: device.id, metric: .temperature, range: try DataKitFixtures.wideRange())

        #expect(!insight.summary.isEmpty)
        #expect(insight.source == .deterministic)
        #expect((0...1).contains(insight.confidence))
    }
}
