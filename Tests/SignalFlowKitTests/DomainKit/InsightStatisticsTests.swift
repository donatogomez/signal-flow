import Foundation
import Testing
import DomainKit

@Suite("Insight statistics grounding")
struct InsightStatisticsTests {

    private func readings(_ values: [Double], metric: MetricKind = .temperature, unit: MeasurementUnit = .celsius) throws -> [TelemetryReading] {
        let id = DeviceID()
        return try values.enumerated().map { index, value in
            TelemetryReading(
                deviceID: id, metric: metric,
                value: try MeasuredValue(magnitude: value, unit: unit),
                recordedAt: Date(timeIntervalSince1970: Double(index) * 60)
            )
        }
    }

    @Test("Computes min/max/average/latest and carries the unit")
    func aggregates() throws {
        let stats = try #require(InsightStatistics.make(from: try readings([2, 4, 6]), metric: .temperature))
        #expect(stats.minimum == 2)
        #expect(stats.maximum == 6)
        #expect(stats.average == 4)
        #expect(stats.latest == 6)
        #expect(stats.sampleCount == 3)
        #expect(stats.unit == .celsius)
    }

    struct TrendCase: Sendable, CustomTestStringConvertible {
        let values: [Double]
        let expected: TrendDirection
        var testDescription: String { "\(expected)" }
    }

    @Test("Classifies trend direction", arguments: [
        TrendCase(values: [1, 2, 3, 4, 5], expected: .rising),
        TrendCase(values: [5, 4, 3, 2, 1], expected: .falling),
        TrendCase(values: [3, 3, 3, 3], expected: .stable),
        TrendCase(values: [1, 10, 1, 10, 1], expected: .volatile),
    ])
    func trend(_ testCase: TrendCase) throws {
        let stats = try #require(InsightStatistics.make(from: try readings(testCase.values), metric: .temperature))
        #expect(stats.trend == testCase.expected)
    }

    @Test("Fewer than two readings yields nil (insufficient data)")
    func insufficient() throws {
        #expect(InsightStatistics.make(from: try readings([5]), metric: .temperature) == nil)
        #expect(InsightStatistics.make(from: [], metric: .temperature) == nil)
    }

    @Test("Only readings of the requested metric are considered")
    func filtersByMetric() throws {
        var mixed = try readings([2, 4])
        let id = mixed[0].deviceID
        mixed.append(TelemetryReading(
            deviceID: id, metric: .humidity,
            value: try MeasuredValue(magnitude: 99, unit: .percent),
            recordedAt: Date(timeIntervalSince1970: 999)
        ))
        let stats = try #require(InsightStatistics.make(from: mixed, metric: .temperature))
        #expect(stats.maximum == 4)   // the humidity 99 is ignored
        #expect(stats.unit == .celsius)
    }
}
