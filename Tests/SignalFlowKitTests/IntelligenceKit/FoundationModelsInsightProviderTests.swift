import Foundation
import Testing
import DomainKit
import DataKit
@testable import IntelligenceKit

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

    @Test("A cancelled request throws instead of falling back, even with the model available")
    func cancellationDoesNotFallBack() async throws {
        let fallback = CountingFallback()
        let provider = FoundationModelsInsightProvider(fallback: fallback, isModelAvailable: { true })
        let ctx = try context()

        // The request starts only after it has been cancelled, so it never reaches the model.
        let gate = Latch()
        let request = Task {
            await gate.wait()
            return try await provider.insight(for: ctx)
        }
        request.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await fallback.calls == 0)
    }

    @Test("Generation errors fall back; cancellation, in either form, doesn't")
    func fallbackDecision() async {
        #expect(FoundationModelsInsightProvider.shouldFallBack(after: CocoaError(.featureUnsupported)))
        #expect(!FoundationModelsInsightProvider.shouldFallBack(after: CancellationError()))

        // A framework error thrown because the task was cancelled is still cancellation.
        let gate = Latch()
        let cancelled = Task {
            await gate.wait()
            return FoundationModelsInsightProvider.shouldFallBack(after: CocoaError(.featureUnsupported))
        }
        cancelled.cancel()
        await gate.open()
        #expect(await cancelled.value == false)
    }

    @Test("The prompt hands the model the grounded advisory level instead of asking it to classify")
    func promptCarriesGroundedSeverity() throws {
        let prompt = FoundationModelsInsightProvider.prompt(for: try context())
        #expect(prompt.contains("Advisory level (already decided, keep your wording consistent with it): nominal"))
        #expect(!prompt.localizedCaseInsensitiveContains("advisory severity"))
    }
}

/// A fallback that counts how often it's asked.
private actor CountingFallback: InsightsProviding {
    private(set) var calls = 0
    func insight(for context: InsightContext) async throws -> DeviceInsight {
        calls += 1
        return try await DeterministicInsightsProvider().insight(for: context)
    }
}
