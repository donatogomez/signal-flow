import Foundation
import DomainKit

/// Minimal, in-memory stub repositories for use-case tests. They return scripted data and record
/// nothing — `DomainKit` ports are simple enough that hand-written stubs beat any mocking framework.
/// (Reusable fakes will graduate to `TestingSupportKit` when more than this layer needs them.)

struct StubDeviceRepository: DeviceRepository {
    var stubDevice: Device
    func devices(inAsset assetID: AssetID) async throws -> [Device] { [stubDevice] }
    func device(_ id: DeviceID) async throws -> Device { stubDevice }
}

struct StubTelemetryRepository: TelemetryRepository {
    var stubLatest: [TelemetryReading] = []
    var stubHistory: [TelemetryReading] = []
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading] { stubLatest }
    func readings(
        forDevice deviceID: DeviceID,
        metric: MetricKind,
        in range: TimeRange
    ) async throws -> [TelemetryReading] { stubHistory }
}

struct StubAlertRepository: AlertRepository {
    var stubActive: [Alert] = []
    var stubRules: [AlertRule] = []
    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert] { stubActive }
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule] { stubRules }
    func record(_ alert: Alert) async throws {}
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {}
}

struct StubAssetRepository: AssetRepository {
    var stubAsset: Asset
    func allAssets() async throws -> [Asset] { [stubAsset] }
    func asset(_ id: AssetID) async throws -> Asset { stubAsset }
}

struct StubEventRepository: EventRepository {
    var stubEvents: [DeviceEvent] = []
    func recentEvents(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent] { stubEvents }
    func recentEvents(limit: Int) async throws -> [DeviceEvent] { stubEvents }
}

struct StubInsightsProvider: InsightsProviding {
    var stubInsight: DeviceInsight
    func insight(for context: InsightContext) async throws -> DeviceInsight { stubInsight }
}
