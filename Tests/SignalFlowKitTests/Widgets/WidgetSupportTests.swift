import Testing
import Foundation
import WidgetKit
import DomainKit
import PersistenceKit
import SnapshotKit
@testable import WidgetSupportKit

@Suite("Widget support")
struct WidgetSupportTests {

    // MARK: - Builders

    private let assetID = AssetID()

    private func device(_ name: String, _ state: ConnectivityStatus.State) throws -> Device {
        try Device(assetID: assetID, name: name, connectivity: ConnectivityStatus(state: state))
    }

    private func alert(
        _ severity: AlertSeverity,
        device: DeviceID,
        message: String = "Threshold breached",
        raisedAt: TimeInterval,
        acknowledged: Bool = false
    ) throws -> Alert {
        var alert = Alert(
            deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: severity,
            message: message, observedValue: try MeasuredValue(magnitude: 10, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: raisedAt)
        )
        if acknowledged { try alert.acknowledge(at: Date(timeIntervalSince1970: raisedAt + 1)) }
        return alert
    }

    private func reading(device: DeviceID, at: TimeInterval) throws -> TelemetryReading {
        TelemetryReading(
            deviceID: device, metric: .temperature,
            value: try MeasuredValue(magnitude: 5, unit: .celsius),
            recordedAt: Date(timeIntervalSince1970: at)
        )
    }

    private func snapshot(devices: [Device], alerts: [Alert], readings: [TelemetryReading] = []) -> PersistedSnapshot {
        PersistedSnapshot(
            assets: [], devices: devices, latestReadings: readings,
            events: [], alerts: alerts, insights: []
        )
    }

    // MARK: - Fleet aggregation

    @Test("Fleet summary buckets devices by the same status the app shows")
    func fleetAggregation() throws {
        let nominal = try device("D1", .online)
        let critical = try device("D2", .online)
        let warning = try device("D3", .degraded)
        let offline = try device("D4", .offline)

        let summary = FleetSummary.make(from: snapshot(
            devices: [nominal, critical, warning, offline],
            alerts: [try alert(.critical, device: critical.id, raisedAt: 1)]
        ))

        #expect(summary.online == 1)
        #expect(summary.critical == 1)
        #expect(summary.warning == 1)
        #expect(summary.offline == 1)
        #expect(summary.total == 4)
    }

    @Test("An acknowledged critical alert no longer drives the critical bucket")
    func acknowledgedAlertDoesNotCount() throws {
        let d = try device("D1", .online)
        let summary = FleetSummary.make(from: snapshot(
            devices: [d],
            alerts: [try alert(.critical, device: d.id, raisedAt: 1, acknowledged: true)]
        ))
        #expect(summary.critical == 0)
        #expect(summary.online == 1)
    }

    @Test("Last-updated reflects the newest reading time")
    func lastUpdated() throws {
        let d = try device("D1", .online)
        let summary = FleetSummary.make(from: snapshot(
            devices: [d], alerts: [],
            readings: [try reading(device: d.id, at: 100), try reading(device: d.id, at: 500)]
        ))
        #expect(summary.lastUpdated == Date(timeIntervalSince1970: 500))
    }

    // MARK: - Alert selection

    @Test("Top alerts: unacknowledged first, then most severe, then most recent — joined with names")
    func alertSelection() throws {
        let truck = try device("Reefer 12", .online)
        let warn = try alert(.warning, device: truck.id, message: "Humidity high", raisedAt: 50)
        let critOld = try alert(.critical, device: truck.id, message: "Temp high", raisedAt: 10)
        let critNew = try alert(.critical, device: truck.id, message: "Temp critical", raisedAt: 100)
        let acked = try alert(.critical, device: truck.id, message: "Old", raisedAt: 200, acknowledged: true)

        let top = WidgetAlert.top(from: snapshot(devices: [truck], alerts: [warn, critOld, critNew, acked]), limit: 3)

        #expect(top.count == 3)
        // Ordering: unacknowledged first, then most severe, then most recent.
        #expect(top.map(\.severity) == [.critical, .critical, .warning])
        #expect(top.map(\.raisedAt) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 50)])
        // The message is now a localized, derived string (not the raw domain message).
        #expect(top.allSatisfy { !$0.message.isEmpty })
        #expect(top.allSatisfy { $0.deviceName == "Reefer 12" })
    }

    @Test("Widget alerts never expose the raw domain alert message")
    func widgetAlertMessageIsLocalized() throws {
        let truck = try device("Reefer 12", .online)
        let rawDomainMessage = "Threshold exceeded — raw domain diagnostic"
        let a = try alert(.critical, device: truck.id, message: rawDomainMessage, raisedAt: 1)

        let top = WidgetAlert.top(from: snapshot(devices: [truck], alerts: [a]), limit: 1)

        let message = try #require(top.first?.message)
        #expect(message != rawDomainMessage)
        #expect(!message.contains("Threshold exceeded"))
        // It's the derived/localized alert text built from metric + observed value.
        #expect(message == AlertText.message(metric: a.metric, value: a.observedValue))
    }

    @Test("Alerts for an unknown device fall back to a placeholder name")
    func alertUnknownDevice() throws {
        let orphan = try alert(.critical, device: DeviceID(), raisedAt: 1)
        let top = WidgetAlert.top(from: snapshot(devices: [], alerts: [orphan]), limit: 5)
        #expect(top.first?.deviceName == "Unknown device")
    }

    // MARK: - Snapshot generation (real in-memory SwiftData via PersistenceKit)

    @Test("Reader builds widget data from persisted state")
    func snapshotGeneration() async throws {
        let store = PersistenceStore(modelContainer: try PersistenceController.makeInMemoryContainer())
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let online = try device("D1", .online)
        let down = try device("D2", .offline)
        try await store.upsertCatalog(assets: [asset], devices: [online, down])
        try await store.replaceActiveAlerts([try alert(.critical, device: online.id, raisedAt: 5)], forDevice: online.id)
        try await store.appendReadings([try reading(device: online.id, at: 999)])

        let data = try await WidgetSnapshotReader(store: store).read(now: Date(timeIntervalSince1970: 1000))

        #expect(data.fleet.critical == 1)
        #expect(data.fleet.offline == 1)
        #expect(data.fleet.lastUpdated == Date(timeIntervalSince1970: 999))
        #expect(data.alerts.first?.deviceName == "D1")
        #expect(data.generatedAt == Date(timeIntervalSince1970: 1000))
    }

    // MARK: - Timeline generation

    @Test("Fleet timeline emits one entry at `now` and a deterministic next reload")
    func fleetTimeline() {
        let now = Date(timeIntervalSince1970: 1000)
        let data = WidgetData(fleet: FleetSummary(online: 3, warning: 0, critical: 1, offline: 0, lastUpdated: now), alerts: [], generatedAt: now)

        let timeline = WidgetTimeline.fleet(data, now: now)

        #expect(timeline.entries.count == 1)
        #expect(timeline.entries.first?.date == now)
        #expect(timeline.entries.first?.fleet == data.fleet)
        #expect(WidgetTimeline.nextReload(after: now) == now.addingTimeInterval(15 * 60))
    }

    @Test("Alerts timeline trims to the requested limit")
    func alertsTimeline() {
        let now = Date(timeIntervalSince1970: 1000)
        let alerts = (0..<6).map {
            WidgetAlert(id: AlertID(), deviceName: "D1", severity: .critical, metric: .temperature, message: "m", raisedAt: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        let data = WidgetData(fleet: .empty, alerts: alerts, generatedAt: now)

        let timeline = WidgetTimeline.alerts(data, now: now, limit: 4)

        #expect(timeline.entries.first?.alerts.count == 4)
    }

    // MARK: - Deep links

    @Test("Widget routes round-trip through their URLs")
    func deepLinks() {
        for route in DeepLinkRoute.allCases {
            #expect(DeepLinkRoute(url: route.url) == route)
        }
        #expect(DeepLinkRoute(url: URL(string: "https://example.com/alerts")!) == nil)
        #expect(DeepLinkRoute.alerts.url.absoluteString == "signalflow://alerts")
    }
}
