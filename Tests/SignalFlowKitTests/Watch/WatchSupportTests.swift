import Testing
import Foundation
import DomainKit
import PersistenceKit
import SnapshotKit
import WatchConnectivityKit
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
        WidgetAlert(id: AlertID(), deviceName: device, severity: severity, metric: .temperature, message: message, raisedAt: Date(timeIntervalSince1970: raisedAt))
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

        // NB: on the macOS test host SwiftPM copies the catalog in uncompiled, so `loc(_:)` resolves the
        // English *source* (the plural rule isn't applied here — "2 warning"). The compiled app shows
        // "2 warnings"; the Spanish/plural translations are asserted against the catalog in `…Catalog`.
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

        // The watch alert row shows the localized, derived message — never the raw domain message.
        let message = try #require(snapshot.alerts.first?.message)
        #expect(message != "Too hot")
        #expect(!message.contains("Threshold exceeded"))
        #expect(message == AlertText.message(metric: .temperature, value: critical.observedValue))
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

    // MARK: - Watch labels (key selection — English source on the test host)

    @Test("Status, severity, and connectivity map to the right catalog labels")
    func watchLabelMapping() {
        #expect(DeviceStatus.nominal.watchLabel == "Online")
        #expect(DeviceStatus.warning.watchLabel == "Warning")
        #expect(DeviceStatus.critical.watchLabel == "Critical")
        #expect(DeviceStatus.offline.watchLabel == "Offline")

        #expect(AlertSeverity.critical.watchLabel == "Critical")
        #expect(AlertSeverity.warning.watchLabel == "Warning")
        #expect(AlertSeverity.info.watchLabel == "Info")

        #expect(ConnectivityStatus.State.online.watchLabel == "Online")
        #expect(ConnectivityStatus.State.degraded.watchLabel == "Degraded")
        #expect(ConnectivityStatus.State.offline.watchLabel == "Offline")
    }

    @Test("Online count summary uses the localizable online key")
    func onlineCountSummary() {
        let model = FleetSummaryViewModel(snapshot(fleet: FleetSummary(online: 8, warning: 1, critical: 1, offline: 0, lastUpdated: nil), alerts: []))
        #expect(model.onlineSummary == "8/10 online")
    }

    // MARK: - Spanish translations (asserted against the shipped catalog, compilation-independent)

    @Test("The watch string catalog carries the expected Spanish labels")
    func spanishCatalogLabels() throws {
        let cat = try Catalog()
        #expect(cat.unit("Online", "es") == "En línea")
        #expect(cat.unit("Warning", "es") == "Advertencia")
        #expect(cat.unit("Critical", "es") == "Crítico")
        #expect(cat.unit("Offline", "es") == "Sin conexión")
        #expect(cat.unit("Degraded", "es") == "Degradada")
        #expect(cat.unit("Info", "es") == "Información")
        #expect(cat.unit("All clear", "es") == "Todo en orden")
        #expect(cat.unit("Battery", "es") == "Batería")
        #expect(cat.unit("Connectivity", "es") == "Conectividad")
        #expect(cat.unit("Last seen", "es") == "Visto por última vez")
        #expect(cat.unit("Telemetry", "es") == "Telemetría")
        #expect(cat.unit("Updated", "es") == "Actualizado")
        #expect(cat.unit("Devices", "es") == "Dispositivos")
        #expect(cat.unit("No devices", "es") == "Sin dispositivos")
        #expect(cat.unit("No active alerts", "es") == "No hay alertas activas")
    }

    @Test("The fleet headline keys are pluralized in Spanish")
    func spanishCatalogHeadlinePlurals() throws {
        let cat = try Catalog()
        #expect(cat.plural("%lld warning", "es", "one") == "%lld advertencia")
        #expect(cat.plural("%lld warning", "es", "other") == "%lld advertencias")
        #expect(cat.plural("%lld critical", "es", "one") == "%lld crítico")
        #expect(cat.plural("%lld critical", "es", "other") == "%lld críticos")
        // English plural is also defined so the compiled app reads "2 warnings".
        #expect(cat.plural("%lld warning", "en", "other") == "%lld warnings")
    }

    @Test("The online-count summary key is localized in Spanish")
    func spanishCatalogOnlineCount() throws {
        let cat = try Catalog()
        #expect(cat.unit("%lld/%lld online", "es") == "%lld/%lld en línea")
    }

    // MARK: - Alert row model

    @Test("Alert row exposes device name, passthrough message, and a severity label")
    func alertRowModel() {
        let row = AlertRowViewModel(alert(.critical, device: "Reefer 12", raisedAt: 1, message: "Temperatura 12.0 °C fuera de rango"))
        #expect(row.deviceName == "Reefer 12")
        #expect(row.message == "Temperatura 12.0 °C fuera de rango")   // already-localized message passes through
        #expect(row.severityLabel == "Critical")                       // English source on the test host
        #expect(row.severity == .critical)
    }

    // MARK: - Device snapshot model

    @Test("Device snapshot model projects status, battery, connectivity and telemetry")
    func deviceSnapshotModel() throws {
        let device = WatchDeviceSnapshot(
            id: DeviceID(),
            name: "Reefer 12",
            assetName: "Fleet A",
            status: .warning,
            battery: try BatteryStatus(percentage: 83.6, isCharging: true),
            connectivity: ConnectivityStatus(state: .degraded, lastSeenAt: Date(timeIntervalSince1970: 1000)),
            telemetry: [
                WatchTelemetryHighlight(metric: .temperature, value: try MeasuredValue(magnitude: 12, unit: .celsius)),
                WatchTelemetryHighlight(metric: .humidity, value: try MeasuredValue(magnitude: 55, unit: .percent)),
            ]
        )

        let vm = DeviceSnapshotViewModel(device)
        #expect(vm.name == "Reefer 12")
        #expect(vm.assetName == "Fleet A")
        #expect(vm.statusLabel == "Warning")
        #expect(vm.batteryText == "84%")          // rounded
        #expect(vm.isCharging == true)
        #expect(vm.connectivityLabel == "Degraded")
        #expect(vm.lastSeenAt == Date(timeIntervalSince1970: 1000))
        #expect(vm.hasTelemetry)
        #expect(vm.telemetry.count == 2)
        #expect(vm.telemetry.first?.name == "Temperature")
        #expect(vm.telemetry.first?.value.contains("°C") == true)
    }

    @Test("Primary metric exposes the value, sparkline history, and a rising trend delta")
    func primaryMetricTrend() throws {
        let device = WatchDeviceSnapshot(
            id: DeviceID(), name: "Reefer 27", assetName: "Fleet A", status: .critical,
            battery: nil, connectivity: ConnectivityStatus(state: .online),
            telemetry: [WatchTelemetryHighlight(
                metric: .temperature,
                value: try MeasuredValue(magnitude: 12.4, unit: .celsius),
                history: [8, 9, 10, 12.4], spanMinutes: 30
            )]
        )
        let primary = try #require(DeviceSnapshotViewModel(device).primaryMetric)
        // Value is locale-formatted (e.g. "12.4 °C" or "12,4 °C"), so assert separator-agnostically.
        #expect(primary.value.contains("12"))
        #expect(primary.value.contains("°C"))
        #expect(primary.history == [8, 9, 10, 12.4])
        #expect(primary.hasTrend)
        #expect(primary.isRising)
        let delta = try #require(primary.deltaText)
        #expect(delta.contains("↑"))
        #expect(delta.contains("4"))     // |12.4 − 8| = 4.4
        #expect(delta.contains("°C"))
        #expect(delta.contains("min"))   // "in 30 min" (English source on the test host)
    }

    @Test("Primary metric omits the delta when there is no recent series")
    func primaryMetricNoTrend() throws {
        let device = WatchDeviceSnapshot(
            id: DeviceID(), name: "D1", assetName: nil, status: .nominal,
            telemetry: [WatchTelemetryHighlight(metric: .temperature, value: try MeasuredValue(magnitude: 8, unit: .celsius))]
        )
        let primary = try #require(DeviceSnapshotViewModel(device).primaryMetric)
        #expect(primary.hasTrend == false)
        #expect(primary.deltaText == nil)
    }

    @Test("Device snapshot model copes with absent battery/telemetry")
    func deviceSnapshotModelMinimal() {
        let device = WatchDeviceSnapshot(id: DeviceID(), name: "D1", assetName: nil, status: .offline)
        let vm = DeviceSnapshotViewModel(device)
        #expect(vm.batteryText == nil)
        #expect(vm.hasBattery == false)
        #expect(vm.hasTelemetry == false)
        #expect(vm.lastSeenAt == nil)
        #expect(vm.statusLabel == "Offline")
        #expect(vm.connectivityLabel == "Offline")
    }

    // MARK: - Device list ordering + empty state

    @Test("Device list orders worst-status-first, then by name")
    func deviceListOrdering() {
        func dev(_ name: String, _ status: DeviceStatus) -> WatchDeviceSnapshot {
            WatchDeviceSnapshot(id: DeviceID(), name: name, assetName: nil, status: status)
        }
        let snap = WatchSnapshot(
            fleet: FleetSummary(online: 1, warning: 1, critical: 1, offline: 1, lastUpdated: nil),
            alerts: [],
            devices: [dev("Bravo", .nominal), dev("Alpha", .warning), dev("Delta", .critical), dev("Charlie", .offline), dev("Echo", .warning)],
            hasData: true
        )
        let model = DeviceListViewModel(snap)
        #expect(model.devices.map(\.status) == [.critical, .warning, .warning, .offline, .nominal])
        // Equal status (.warning) falls back to name order: Alpha before Echo.
        #expect(model.devices.filter { $0.status == .warning }.map(\.name) == ["Alpha", "Echo"])
    }

    @Test("Device list reports empty when no devices synced")
    func deviceListEmpty() {
        #expect(DeviceListViewModel(.empty).isEmpty)
        #expect(DeviceListViewModel(snapshot(fleet: FleetSummary(online: 2, warning: 0, critical: 0, offline: 0, lastUpdated: nil), alerts: [])).isEmpty) // WidgetData path carries no devices
    }
}

private struct StubProvider: WatchSnapshotProviding {
    let snapshot: WatchSnapshot
    func load() async -> WatchSnapshot { snapshot }
}

/// Reads the shipped `Localizable.xcstrings` straight from the WatchSupportKit resource bundle. SwiftPM
/// copies the catalog in uncompiled, so this asserts the translations at their source — independent of
/// the macOS test host's process language and of plural compilation.
private struct Catalog {
    private let strings: [String: Any]

    init() throws {
        let url = try #require(watchSupportResourceBundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        strings = (json?["strings"] as? [String: Any]) ?? [:]
    }

    private func localization(_ key: String, _ language: String) -> [String: Any]? {
        let entry = strings[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        return localizations?[language] as? [String: Any]
    }

    /// The plain translated value for a non-plural key.
    func unit(_ key: String, _ language: String) -> String? {
        (localization(key, language)?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// The translated value for a given plural category ("one" / "other").
    func plural(_ key: String, _ language: String, _ category: String) -> String? {
        let variations = (localization(key, language)?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        let unit = (variations?[category] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }
}
