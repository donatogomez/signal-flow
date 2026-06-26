import Testing
import Foundation
import DomainKit
@testable import FeatureAlerts

@MainActor
@Suite("Alerts model")
struct AlertsModelTests {

    // MARK: - Fixtures

    private func alert(
        _ severity: AlertSeverity,
        device: DeviceID,
        raisedAt: TimeInterval = 1,
        acknowledged: Bool = false
    ) throws -> Alert {
        var alert = Alert(
            deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: severity,
            message: "\(severity) on temperature",
            observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: raisedAt)
        )
        if acknowledged { try alert.acknowledge(at: Date(timeIntervalSince1970: raisedAt + 1)) }
        return alert
    }

    /// Builds a model wired over fakes for a single device in a single asset. `deviceID`/`assetID`
    /// are surfaced so the caller can craft alerts that line up with the device's context.
    private func makeModel(
        deviceID: DeviceID,
        assetID: AssetID,
        active: [Alert],
        history: [Alert] = [],
        throwing: Bool = false
    ) throws -> (AlertsModel, StatefulAlertRepository) {
        let device = try FX.device("Reefer 12", asset: assetID, id: deviceID)
        let assets: any AssetRepository = throwing
            ? ThrowingAssetRepository()
            : FakeAssetRepository(
                byID: [assetID: try FX.asset("Greenhouse A", .greenhouse, id: assetID, devices: [deviceID])],
                order: [assetID]
            )
        let devices = FakeDeviceRepository(byAsset: [assetID: [device]], byID: [deviceID: device])
        let repo = StatefulAlertRepository(active)
        let model = AlertsModel(
            assets: assets, devices: devices, alerts: repo,
            alertHistory: FakeAlertHistoryProvider(alerts: history),
            now: { Date(timeIntervalSince1970: 500) }
        )
        return (model, repo)
    }

    // MARK: - Loading

    @Test("Loads active alerts with device and asset context")
    func loadsActiveAlerts() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(deviceID: deviceID, assetID: assetID, active: [try alert(.critical, device: deviceID)])

        await model.refresh()

        #expect(model.phase == .loaded)
        #expect(model.active.count == 1)
        let row = try #require(model.active.first)
        #expect(row.deviceName == "Reefer 12")
        #expect(row.assetName == "Greenhouse A")
        #expect(row.severity == .critical)
        #expect(!row.isAcknowledged)
    }

    @Test("Loads resolved alerts into history")
    func loadsHistory() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(
            deviceID: deviceID, assetID: assetID,
            active: [], history: [try alert(.warning, device: deviceID, raisedAt: 100)]
        )

        await model.refresh()
        model.tab = .resolved

        #expect(model.history.count == 1)
        #expect(model.visibleAlerts.count == 1)
        #expect(model.history.first?.assetName == "Greenhouse A")
    }

    // MARK: - Filtering

    @Test("Severity filter narrows the visible list")
    func filtersBySeverity() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(
            deviceID: deviceID, assetID: assetID,
            active: [try alert(.critical, device: deviceID, raisedAt: 1), try alert(.warning, device: deviceID, raisedAt: 2)]
        )

        await model.refresh()
        #expect(model.visibleAlerts.count == 2)

        model.severityFilter = .warning
        #expect(model.visibleAlerts.count == 1)
        #expect(model.visibleAlerts.first?.severity == .warning)
    }

    // MARK: - Acknowledge

    @Test("Acknowledging an alert updates the row deterministically")
    func acknowledgeUpdatesRow() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(deviceID: deviceID, assetID: assetID, active: [try alert(.critical, device: deviceID)])

        await model.refresh()
        let id = try #require(model.active.first?.id)
        #expect(model.unacknowledgedActiveCount == 1)

        await model.acknowledge(id)

        let row = try #require(model.active.first { $0.id == id })
        #expect(row.isAcknowledged)
        #expect(model.unacknowledgedActiveCount == 0)
    }

    @Test("Unacknowledged alerts sort ahead of more-severe acknowledged ones")
    func ordersUnacknowledgedFirst() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(
            deviceID: deviceID, assetID: assetID,
            active: [
                try alert(.critical, device: deviceID, raisedAt: 1, acknowledged: true),
                try alert(.warning, device: deviceID, raisedAt: 2, acknowledged: false)
            ]
        )

        await model.refresh()

        #expect(model.active.first?.severity == .warning)
        #expect(model.active.first?.isAcknowledged == false)
    }

    // MARK: - Empty & error states

    @Test("Reports loaded with no rows when the fleet is healthy")
    func emptyState() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(deviceID: deviceID, assetID: assetID, active: [])

        await model.refresh()

        #expect(model.phase == .loaded)
        #expect(model.active.isEmpty)
        #expect(model.visibleAlerts.isEmpty)
    }

    @Test("Surfaces a failure when a repository throws")
    func errorState() async throws {
        let deviceID = DeviceID(), assetID = AssetID()
        let (model, _) = try makeModel(deviceID: deviceID, assetID: assetID, active: [], throwing: true)

        await model.refresh()

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }
}
