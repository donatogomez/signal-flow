import Foundation
import Testing
import DomainKit
import DataKit
import IntelligenceKit

/// These tests never invoke the on-device model — they force the unavailable path so they're
/// deterministic and pass on CI machines without Apple Intelligence.
@Suite("Foundation Models insight provider")
struct FoundationModelsInsightProviderTests {

    private func context() throws -> InsightContext {
        let stats = InsightStatistics(
            metric: .temperature, unit: .celsius, latest: 4, minimum: 2, maximum: 6,
            average: 4, trend: .stable, sampleCount: 12
        )
        return InsightContext(
            deviceID: DeviceID(),
            deviceName: "Reefer 12", assetKind: .refrigeratedTruck, statistics: stats,
            activeAlertCount: 0, recentEventCount: 0,
            range: try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1000))
        )
    }

    @Test("When the model is unavailable, it falls back to the deterministic provider")
    func unavailableFallsBack() async throws {
        let provider = FoundationModelsInsightProvider(
            fallback: DeterministicInsightsProvider(),
            isModelAvailable: { false }
        )
        let insight = try await provider.insight(for: try context())
        #expect(insight.source == .deterministic)
        #expect(!insight.summary.isEmpty)
    }

    @Test("The fallback output matches the deterministic provider's own output")
    func fallbackEqualsDeterministic() async throws {
        let ctx = try context()
        let viaFoundationModels = try await FoundationModelsInsightProvider(
            fallback: DeterministicInsightsProvider(),
            isModelAvailable: { false }
        ).insight(for: ctx)
        let direct = try await DeterministicInsightsProvider().insight(for: ctx)
        #expect(viaFoundationModels == direct)
    }
}
