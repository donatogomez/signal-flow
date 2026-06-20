import Testing
import Foundation
import DomainKit
import PersistenceKit
import SnapshotKit
@testable import WatchSupportKit

@Suite("watchOS companion")
struct WatchSupportTests {

    // MARK: - Builders

    private func alert(
        _ severity: AlertSeverity,
        device: String = "Reefer 12",
        raisedAt: TimeInterval,
        message: String = "Threshold breached"
    ) -> WidgetAlert {
        WidgetAlert(id: AlertID(), deviceName: device, severity: severity, message: message, raisedAt: Date(timeIntervalSince1970: raisedAt))
    }

    private func snapshot(fleet: FleetSummary, alerts: [WidgetAlert]) -> WatchSnapshot {
        .from(WidgetData(fleet: fleet, alerts: alerts, generatedAt: .distantPast))
    }

    // MARK: - Fleet summary model

    @Test("Fleet summary projects counts and a severity-first headline")
    func fleetSummaryModel() {
        let healthy = FleetSummaryViewModel(snapshot(fleet: FleetSummary(online: 9, warning: 0, critical: 0, offline: 0, lastUpdated: nil), alerts: []))
        #expect(healthy.total == 9)
        #expect(healthy.headline == "All clear")
        #expect(healthy.hasAlerts == false)

        let warning = FleetSummaryViewModel(snapshot(fleet: FleetSummary(online: 7, warning: 2, critical: 0, offline: 0, lastUpdated: nil), alerts: [alert(.warning, raisedAt: 1)]))
        #expect(warning.headline == "2 warning")

        let critical = FleetSummaryViewModel(snapshot(fleet: FleetSummary(online: 6, warning: 2, critical: 1, offline: 1, lastUpdated: nil), alerts: [alert(.critical, raisedAt: 1)]))
        #expect(critical.headline == "1 critical")
        #expect(critical.hasAlerts == true)
        #expect(critical.alertCount == 1)
    }

    // MARK: - Empty state

    @Test("A fleet with no devices is treated as no-data (empty state)")
    func emptyState() {
        let model = FleetSummaryViewModel(.empty)
        #expect(model.hasData == false)
        #expect(model.headline == "No data")
        #expect(WatchSnapshot.from(WidgetData.empty(now: .distantPast)).hasData == false)
    }

    // MARK: - Alert list model + severity ordering

    @Test("Alert list orders by severity, then recency")
    func alertSeverityOrdering() {
        let warnNew = alert(.warning, raisedAt: 100)
        let critOld = alert(.critical, raisedAt: 10)
        let critNew = alert(.critical, raisedAt: 50)
        let info = alert(.info, raisedAt: 200)

        let model = AlertListViewModel(snapshot(
            fleet: FleetSummary(online: 1, warning: 1, critical: 2, offline: 0, lastUpdated: nil),
            alerts: [warnNew, critOld, info, critNew]
        ))

        #expect(model.alerts.map(\.severity) == [.critical, .critical, .warning, .info])
        #expect(model.alerts.first?.raisedAt == Date(timeIntervalSince1970: 50)) // newer critical first
        #expect(model.isEmpty == false)
    }

    // MARK: - Snapshot provider behavior

    @Test("Provider reads persisted state and reports data")
    func providerReadsPersistedSnapshot() async throws {
        let assetID = AssetID()
        let store = PersistenceStore(modelContainer: try PersistenceController.makeInMemoryContainer())
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let online = try Device(assetID: assetID, name: "D1", connectivity: ConnectivityStatus(state: .online))
        let down = try Device(assetID: assetID, name: "D2", connectivity: ConnectivityStatus(state: .offline))
        try await store.upsertCatalog(assets: [asset], devices: [online, down])
        let critical = Alert(
            deviceID: online.id, ruleID: AlertRuleID(), metric: .temperature, severity: .critical,
            message: "Too hot", observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: 5)
        )
        try await store.replaceActiveAlerts([critical], forDevice: online.id)

        let provider = PersistedWatchSnapshotProvider(reader: WidgetSnapshotReader(store: store))
        let snapshot = await provider.load()

        #expect(snapshot.hasData == true)
        #expect(snapshot.fleet.total == 2)
        #expect(snapshot.fleet.critical == 1)
        #expect(snapshot.alerts.count == 1)
        #expect(snapshot.alerts.first?.deviceName == "D1")
    }

    @Test("Provider reports no-data for an empty store")
    func providerEmptyStore() async throws {
        let store = PersistenceStore(modelContainer: try PersistenceController.makeInMemoryContainer())
        let provider = PersistedWatchSnapshotProvider(reader: WidgetSnapshotReader(store: store))

        let snapshot = await provider.load()

        #expect(snapshot.hasData == false)
        #expect(snapshot.alerts.isEmpty)
    }

    // MARK: - Store

    @MainActor
    @Test("Store loads a snapshot through its provider")
    func storeRefresh() async {
        let model = FleetSummary(online: 3, warning: 1, critical: 1, offline: 0, lastUpdated: nil)
        let store = WatchStore(provider: StubProvider(snapshot: snapshot(fleet: model, alerts: [alert(.critical, raisedAt: 1)])))

        await store.refresh()

        #expect(store.phase == .loaded)
        #expect(store.hasData)
        #expect(store.fleet.critical == 1)
        #expect(store.alertList.alerts.count == 1)
    }
}

private struct StubProvider: WatchSnapshotProviding {
    let snapshot: WatchSnapshot
    func load() async -> WatchSnapshot { snapshot }
}
