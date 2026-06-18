import Foundation
import Testing
import DomainKit
import DataKit

@Suite("Deterministic insights provider")
struct DeterministicInsightsProviderTests {

    private let provider = DeterministicInsightsProvider()

    private func readings(_ values: [Double]) throws -> [TelemetryReading] {
        let id = DeviceID()
        return try values.enumerated().map { index, value in
            try DataKitFixtures.reading(deviceID: id, .temperature, value, at: TimeInterval(index * 60))
        }
    }

    @Test("A steadily increasing series reads as rising")
    func rising() async throws {
        let readings = try readings([1, 2, 3, 4, 5, 6])
        let range = try TimeRange(start: readings.first!.recordedAt, end: readings.last!.recordedAt)
        let insight = try await provider.summarize(readings, for: .temperature, over: range)
        #expect(insight.trend == .rising)
        #expect(insight.confidence > 0)
    }

    @Test("A flat series reads as stable")
    func stable() async throws {
        let readings = try readings([5, 5, 5, 5])
        let range = try TimeRange(start: readings.first!.recordedAt, end: readings.last!.recordedAt)
        #expect(try await provider.summarize(readings, for: .temperature, over: range).trend == .stable)
    }

    @Test("Fewer than two readings is insufficient data")
    func insufficient() async throws {
        let readings = try readings([5])
        let range = try DataKitFixtures.wideRange()
        await #expect(throws: DomainError.insufficientData) {
            _ = try await provider.summarize(readings, for: .temperature, over: range)
        }
    }

    @Test("Insights are reachable through the GenerateTelemetryInsight use case")
    func viaUseCase() async throws {
        let source = SimulatedDataSource.deterministic(seed: 3, maxTicks: 40)
        try await source.bootstrap()
        await source.ingestAll()
        let asset = try #require(try await source.assets.allAssets().first)
        let device = try #require(try await source.devices.devices(inAsset: asset.id).first)

        let insight = try await GenerateTelemetryInsightUseCase(
            telemetry: source.telemetry, insights: source.insights
        )(deviceID: device.id, metric: .temperature, range: try DataKitFixtures.wideRange())

        #expect(!insight.summary.isEmpty)
        #expect((0...1).contains(insight.confidence))
    }
}
