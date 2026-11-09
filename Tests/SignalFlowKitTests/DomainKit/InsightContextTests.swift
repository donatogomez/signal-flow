import Foundation
import Testing
import DomainKit

@Suite("Insight advisory severity (grounded)")
struct InsightContextTests {

    private func context(trend: TrendDirection, activeAlerts: Int) throws -> InsightContext {
        let stats = InsightStatistics(
            metric: .temperature, unit: .celsius, latest: 2.1, minimum: 1.8, maximum: 4.0,
            average: 2.9, trend: trend, sampleCount: 613
        )
        return InsightContext(
            deviceID: DeviceID(), deviceName: "Reefer", assetKind: .refrigeratedTruck, statistics: stats,
            activeAlertCount: activeAlerts, recentEventCount: 0,
            range: try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1000))
        )
    }

    /// Regression: an alert-free device with a clean falling trend (a reefer cooling down) used to be
    /// shown as a red "concern" because the on-device model chose the severity with no thresholds to
    /// ground it. A steady directional trend with no active alerts is nominal.
    @Test("No alerts and a directional or steady trend is nominal", arguments: [TrendDirection.falling, .rising, .stable])
    func calmIsNominal(trend: TrendDirection) throws {
        #expect(try context(trend: trend, activeAlerts: 0).advisorySeverity == .nominal)
    }

    @Test("A volatile trend without alerts is a watch")
    func volatileIsWatch() throws {
        #expect(try context(trend: .volatile, activeAlerts: 0).advisorySeverity == .watch)
    }

    @Test("Any active alert makes it a concern, whatever the trend", arguments: TrendDirection.allCases)
    func alertsAreConcern(trend: TrendDirection) throws {
        #expect(try context(trend: trend, activeAlerts: 1).advisorySeverity == .concern)
    }
}
