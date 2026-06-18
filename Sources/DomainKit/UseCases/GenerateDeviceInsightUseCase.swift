/// Assembles the grounded facts for a device's metric and asks an ``InsightsProviding`` to turn them
/// into a ``DeviceInsight``.
///
/// All statistics are computed here in Swift (via ``InsightStatistics``); the provider only phrases
/// them. Alert and event counts come from repositories that already evaluated them deterministically,
/// so no judgement is delegated to a model.
public struct GenerateDeviceInsightUseCase: Sendable {
    private let devices: any DeviceRepository
    private let assets: any AssetRepository
    private let telemetry: any TelemetryRepository
    private let alerts: any AlertRepository
    private let events: any EventRepository
    private let insights: any InsightsProviding

    public init(
        devices: any DeviceRepository,
        assets: any AssetRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        events: any EventRepository,
        insights: any InsightsProviding
    ) {
        self.devices = devices
        self.assets = assets
        self.telemetry = telemetry
        self.alerts = alerts
        self.events = events
        self.insights = insights
    }

    public func callAsFunction(
        deviceID: DeviceID,
        metric: MetricKind,
        range: TimeRange
    ) async throws -> DeviceInsight {
        let history = try await telemetry.readings(forDevice: deviceID, metric: metric, in: range)
        guard let statistics = InsightStatistics.make(from: history, metric: metric) else {
            throw DomainError.insufficientData
        }

        let device = try await devices.device(deviceID)
        // The asset (for its kind) plus the alert/event counts are independent reads.
        async let assetTask = assets.asset(device.assetID)
        async let alertsTask = alerts.activeAlerts(forDevice: deviceID)
        async let eventsTask = events.recentEvents(forDevice: deviceID, limit: 50)

        let context = InsightContext(
            deviceName: device.name,
            assetKind: try await assetTask.kind,
            statistics: statistics,
            activeAlertCount: try await alertsTask.count,
            recentEventCount: try await eventsTask.count,
            range: range
        )
        return try await insights.insight(for: context)
    }
}
