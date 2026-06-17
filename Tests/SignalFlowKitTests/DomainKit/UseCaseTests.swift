import Foundation
import Testing
import DomainKit

@Suite("Use cases")
struct UseCaseTests {

    @Test("EvaluateAlertRules raises an alert when the latest reading breaches a rule")
    func evaluateAlertRulesRaisesBreach() async throws {
        let deviceID = DeviceID()
        let telemetry = StubTelemetryRepository(
            stubLatest: [try Fixtures.temperatureReading(7.5, deviceID: deviceID)]
        )
        let alerts = StubAlertRepository(stubRules: [try Fixtures.temperatureRule(max: 4)])
        let fixedAlertID = AlertID()

        let useCase = EvaluateAlertRulesUseCase(
            telemetry: telemetry,
            alerts: alerts,
            now: { Fixtures.referenceDate },
            makeAlertID: { fixedAlertID }
        )

        let raised = try await useCase(forDevice: deviceID)
        #expect(raised.count == 1)
        #expect(raised.first?.id == fixedAlertID)
        #expect(raised.first?.severity == .critical)
    }

    @Test("EvaluateAlertRules stays silent when readings are within range")
    func evaluateAlertRulesSilentWhenNominal() async throws {
        let deviceID = DeviceID()
        let telemetry = StubTelemetryRepository(
            stubLatest: [try Fixtures.temperatureReading(2.0, deviceID: deviceID)]
        )
        let alerts = StubAlertRepository(stubRules: [try Fixtures.temperatureRule(max: 4)])
        let useCase = EvaluateAlertRulesUseCase(telemetry: telemetry, alerts: alerts)

        #expect(try await useCase(forDevice: deviceID).isEmpty)
    }

    @Test("FetchDeviceDetail derives status from connectivity and active alerts")
    func fetchDeviceDetailDerivesStatus() async throws {
        let deviceID = DeviceID()
        let device = try Fixtures.device(id: deviceID, connectivity: ConnectivityStatus(state: .online))
        let criticalAlert = Alert(
            deviceID: deviceID,
            ruleID: AlertRuleID(),
            metric: .temperature,
            severity: .critical,
            message: "too hot",
            observedValue: try MeasuredValue(magnitude: 9, unit: .celsius),
            raisedAt: Fixtures.referenceDate
        )

        let useCase = FetchDeviceDetailUseCase(
            devices: StubDeviceRepository(stubDevice: device),
            telemetry: StubTelemetryRepository(
                stubLatest: [try Fixtures.temperatureReading(9, deviceID: deviceID)]
            ),
            alerts: StubAlertRepository(stubActive: [criticalAlert])
        )

        let detail = try await useCase(deviceID: deviceID)
        #expect(detail.status == .critical)
        #expect(detail.latestReadings.count == 1)
        #expect(detail.activeAlerts.count == 1)
    }

    @Test("FetchTelemetryHistory returns readings ordered oldest-first")
    func fetchHistorySorts() async throws {
        let deviceID = DeviceID()
        let unordered = [
            try Fixtures.temperatureReading(3, deviceID: deviceID, at: 300),
            try Fixtures.temperatureReading(1, deviceID: deviceID, at: 100),
            try Fixtures.temperatureReading(2, deviceID: deviceID, at: 200),
        ]
        let useCase = FetchTelemetryHistoryUseCase(
            telemetry: StubTelemetryRepository(stubHistory: unordered)
        )
        let range = try TimeRange(
            start: Fixtures.referenceDate,
            end: Fixtures.referenceDate.addingTimeInterval(1000)
        )

        let history = try await useCase(deviceID: deviceID, metric: .temperature, range: range)
        #expect(history.map(\.value.magnitude) == [1, 2, 3])
    }

    @Test("GenerateTelemetryInsight requires at least two readings")
    func insightRequiresData() async throws {
        let deviceID = DeviceID()
        let insight = TelemetryInsight(summary: "stable", trend: .stable, confidence: 0.9)
        let useCase = GenerateTelemetryInsightUseCase(
            telemetry: StubTelemetryRepository(
                stubHistory: [try Fixtures.temperatureReading(3, deviceID: deviceID)]
            ),
            insights: StubInsightsProvider(stubInsight: insight)
        )
        let range = try TimeRange(
            start: Fixtures.referenceDate,
            end: Fixtures.referenceDate.addingTimeInterval(1000)
        )

        await #expect(throws: DomainError.insufficientData) {
            _ = try await useCase(deviceID: deviceID, metric: .temperature, range: range)
        }
    }

    @Test("GenerateTelemetryInsight delegates to the insights provider when data suffices")
    func insightDelegates() async throws {
        let deviceID = DeviceID()
        let expected = TelemetryInsight(summary: "rising overnight", trend: .rising, confidence: 0.7)
        let useCase = GenerateTelemetryInsightUseCase(
            telemetry: StubTelemetryRepository(stubHistory: [
                try Fixtures.temperatureReading(2, deviceID: deviceID, at: 0),
                try Fixtures.temperatureReading(5, deviceID: deviceID, at: 600),
            ]),
            insights: StubInsightsProvider(stubInsight: expected)
        )
        let range = try TimeRange(
            start: Fixtures.referenceDate,
            end: Fixtures.referenceDate.addingTimeInterval(1000)
        )

        let result = try await useCase(deviceID: deviceID, metric: .temperature, range: range)
        #expect(result == expected)
    }
}
