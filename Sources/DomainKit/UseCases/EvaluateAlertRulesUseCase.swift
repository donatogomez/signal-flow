import Foundation

/// Evaluates a device's alert rules against its latest readings and returns the alerts to raise.
///
/// The clock and id generator are injected as `@Sendable` closures so the use case is deterministic
/// and testable — production passes real ones, tests pass fixed values. The breach logic itself is a
/// pure static function (``evaluate(readings:rules:deviceID:now:makeAlertID:)``) with no I/O.
public struct EvaluateAlertRulesUseCase: Sendable {
    private let telemetry: any TelemetryRepository
    private let alerts: any AlertRepository
    private let now: @Sendable () -> Date
    private let makeAlertID: @Sendable () -> AlertID

    public init(
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        now: @escaping @Sendable () -> Date = { Date() },
        makeAlertID: @escaping @Sendable () -> AlertID = { AlertID() }
    ) {
        self.telemetry = telemetry
        self.alerts = alerts
        self.now = now
        self.makeAlertID = makeAlertID
    }

    public func callAsFunction(forDevice deviceID: DeviceID) async throws -> [Alert] {
        async let readings = telemetry.latestReadings(forDevice: deviceID)
        async let rules = alerts.rules(forDevice: deviceID)
        return Self.evaluate(
            readings: try await readings,
            rules: try await rules,
            deviceID: deviceID,
            now: now(),
            makeAlertID: makeAlertID
        )
    }

    /// Pure evaluation: pairs each rule with the latest reading for its metric and collects breaches.
    public static func evaluate(
        readings: [TelemetryReading],
        rules: [AlertRule],
        deviceID: DeviceID,
        now: Date,
        makeAlertID: () -> AlertID
    ) -> [Alert] {
        let latestByMetric = Dictionary(
            readings.map { ($0.metric, $0) },
            uniquingKeysWith: { $0.recordedAt >= $1.recordedAt ? $0 : $1 }
        )
        return rules.compactMap { rule in
            guard let reading = latestByMetric[rule.metric] else { return nil }
            return rule.evaluate(reading.value, on: deviceID, at: now, alertID: makeAlertID())
        }
    }
}
