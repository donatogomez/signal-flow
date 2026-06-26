import Testing
import Foundation
import DomainKit
import PersistenceKit
import SnapshotKit
import WatchSupportKit
import WatchConnectivityKit

@Suite("WatchConnectivity sync")
struct WatchConnectivitySyncTests {

    // MARK: - Builders

    private let assetID = AssetID()

    private func device(_ name: String, _ state: ConnectivityStatus.State) throws -> Device {
        try Device(assetID: assetID, name: name, connectivity: ConnectivityStatus(state: state))
    }

    private func criticalAlert(device: DeviceID, raisedAt: TimeInterval = 1) throws -> Alert {
        Alert(
            deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: .critical,
            message: "raw domain message", observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: raisedAt)
        )
    }

    private func sampleSnapshot(lastUpdated: Date) -> WatchSyncSnapshot {
        WatchSyncSnapshot(
            fleet: FleetSummary(online: 3, warning: 1, critical: 1, offline: 0, lastUpdated: nil),
            devices: [WatchDeviceSnapshot(id: DeviceID(), name: "D1", assetName: "Fleet A", status: .critical)],
            criticalAlerts: [WidgetAlert(id: AlertID(), deviceName: "D1", severity: .critical, metric: .temperature, message: "m", raisedAt: Date(timeIntervalSince1970: 1))],
            lastUpdated: lastUpdated
        )
    }

    private func tempStore() -> WatchSyncSnapshotStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "wc-\(UUID().uuidString).json")
        return WatchSyncSnapshotStore(fileURL: url)
    }

    // MARK: - Snapshot encoding / decoding

    @Test("Snapshot round-trips through Codable JSON")
    func codecRoundTrip() throws {
        let snapshot = sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 1000))
        let decoded = try WatchSnapshotCodec.decode(WatchSnapshotCodec.encode(snapshot))
        #expect(decoded == snapshot)
    }

    // MARK: - iPhone snapshot construction

    @Test("iPhone builds a compact snapshot from persisted fleet state")
    func buildsFromPersistedSnapshot() throws {
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let online = try device("D1", .online)
        let down = try device("D2", .offline)
        let critDevice = try device("D3", .online)
        let alert = try criticalAlert(device: critDevice.id)
        let persisted = PersistedSnapshot(
            assets: [asset], devices: [online, down, critDevice],
            latestReadings: [], events: [], alerts: [alert], insights: []
        )

        let synced = WatchSnapshotBuilder.build(from: persisted, now: Date(timeIntervalSince1970: 500))

        #expect(synced.fleet.total == 3)
        #expect(synced.fleet.critical == 1)
        #expect(synced.fleet.offline == 1)
        #expect(synced.devices.count == 3)
        #expect(synced.devices.contains { $0.name == "D1" && $0.assetName == "Fleet A" && $0.status == .nominal })
        #expect(synced.criticalAlerts.count == 1)
        #expect(synced.criticalAlerts.allSatisfy { $0.severity == .critical })
        #expect(synced.lastUpdated == Date(timeIntervalSince1970: 500))
        #expect(synced.hasData)
    }

    @Test("The watch inbox receives warnings as well as criticals (info stays on the phone)")
    func buildsIncludeWarnings() throws {
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let dev = try device("D1", .online)
        func alert(_ severity: AlertSeverity) throws -> Alert {
            Alert(deviceID: dev.id, ruleID: AlertRuleID(), metric: .temperature, severity: severity,
                  message: "m", observedValue: try MeasuredValue(magnitude: 5, unit: .celsius), raisedAt: Date(timeIntervalSince1970: 1))
        }
        let persisted = PersistedSnapshot(
            assets: [asset], devices: [dev], latestReadings: [],
            events: [], alerts: [try alert(.warning), try alert(.critical), try alert(.info)], insights: []
        )

        let synced = WatchSnapshotBuilder.build(from: persisted, now: Date(timeIntervalSince1970: 500))
        let severities = Set(synced.criticalAlerts.map(\.severity))

        #expect(severities.contains(.warning))
        #expect(severities.contains(.critical))
        #expect(!severities.contains(.info)) // info-level notices stay on the phone
    }

    @Test("primaryMetric picks the highest-priority metric present")
    func primaryMetricSelection() throws {
        let dev = DeviceID()
        func reading(_ metric: MetricKind) throws -> TelemetryReading {
            TelemetryReading(deviceID: dev, metric: metric, value: try MeasuredValue(magnitude: 1, unit: .celsius), recordedAt: .distantPast)
        }
        #expect(WatchSnapshotBuilder.primaryMetric(of: [try reading(.humidity), try reading(.temperature)]) == .temperature)
        #expect(WatchSnapshotBuilder.primaryMetric(of: [try reading(.batteryLevel), try reading(.humidity)]) == .humidity)
        #expect(WatchSnapshotBuilder.primaryMetric(of: []) == nil)
    }

    @Test("Builder attaches the primary metric's recent history (sparkline + span) to its highlight")
    func buildAttachesTrend() throws {
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let dev = try device("D1", .online)
        func temp(_ magnitude: Double, _ seconds: TimeInterval) throws -> TelemetryReading {
            TelemetryReading(deviceID: dev.id, metric: .temperature, value: try MeasuredValue(magnitude: magnitude, unit: .celsius), recordedAt: Date(timeIntervalSince1970: seconds))
        }
        let series = [try temp(8, 0), try temp(9, 600), try temp(10, 1200), try temp(12.4, 1800)] // 0…1800s = 30 min
        let persisted = PersistedSnapshot(
            assets: [asset], devices: [dev], latestReadings: [series.last!],
            events: [], alerts: [], insights: []
        )

        let synced = WatchSnapshotBuilder.build(from: persisted, now: Date(timeIntervalSince1970: 2000), history: [dev.id: series])
        let highlight = try #require(synced.devices.first?.telemetry.first)

        #expect(highlight.metric == .temperature)
        #expect(highlight.history == [8, 9, 10, 12.4])
        #expect(highlight.spanMinutes == 30)
    }

    @Test("Builder attaches a separate trend to each metric (temperature and humidity)")
    func buildAttachesTrendPerMetric() throws {
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .greenhouse, deviceIDs: [])
        let dev = try device("D1", .online)
        func reading(_ metric: MetricKind, _ unit: MeasurementUnit, _ magnitude: Double, _ seconds: TimeInterval) throws -> TelemetryReading {
            TelemetryReading(deviceID: dev.id, metric: metric, value: try MeasuredValue(magnitude: magnitude, unit: unit), recordedAt: Date(timeIntervalSince1970: seconds))
        }
        let tempSeries = [try reading(.temperature, .celsius, 8, 0), try reading(.temperature, .celsius, 12, 600)]
        let humSeries = [try reading(.humidity, .percent, 40, 0), try reading(.humidity, .percent, 43, 600)]
        let persisted = PersistedSnapshot(
            assets: [asset], devices: [dev],
            latestReadings: [tempSeries.last!, humSeries.last!], events: [], alerts: [], insights: []
        )

        let synced = WatchSnapshotBuilder.build(from: persisted, now: Date(timeIntervalSince1970: 2000),
                                                history: [dev.id: tempSeries + humSeries])
        let snap = try #require(synced.devices.first)

        #expect(snap.telemetry.map(\.metric) == [.temperature, .humidity])
        #expect(snap.telemetry.first { $0.metric == .temperature }?.history == [8, 12])
        #expect(snap.telemetry.first { $0.metric == .humidity }?.history == [40, 43])
    }

    @Test("iPhone enriches each device snapshot with battery, connectivity, and telemetry highlights")
    func buildsEnrichedDeviceSnapshots() throws {
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .greenhouse, deviceIDs: [])
        let device = try Device(
            assetID: assetID,
            name: "Greenhouse 1",
            battery: try BatteryStatus(percentage: 42, isCharging: false),
            connectivity: ConnectivityStatus(state: .degraded, lastSeenAt: Date(timeIntervalSince1970: 900))
        )
        let readings = [
            TelemetryReading(deviceID: device.id, metric: .humidity, value: try MeasuredValue(magnitude: 60, unit: .percent), recordedAt: Date(timeIntervalSince1970: 10)),
            TelemetryReading(deviceID: device.id, metric: .temperature, value: try MeasuredValue(magnitude: 21, unit: .celsius), recordedAt: Date(timeIntervalSince1970: 20)),
            // an older temperature reading must be superseded by the newer one above
            TelemetryReading(deviceID: device.id, metric: .temperature, value: try MeasuredValue(magnitude: 5, unit: .celsius), recordedAt: Date(timeIntervalSince1970: 1)),
        ]
        let persisted = PersistedSnapshot(
            assets: [asset], devices: [device],
            latestReadings: readings, events: [], alerts: [], insights: []
        )

        let synced = WatchSnapshotBuilder.build(from: persisted, now: Date(timeIntervalSince1970: 500))
        let snap = try #require(synced.devices.first)

        #expect(snap.battery?.percentage == 42)
        #expect(snap.connectivity.state == .degraded)
        #expect(snap.lastSeenAt == Date(timeIntervalSince1970: 900))
        // Newest reading per metric, environmental-priority ordered (temperature before humidity).
        #expect(snap.telemetry.map(\.metric) == [.temperature, .humidity])
        #expect(snap.telemetry.first?.value.magnitude == 21)

        // And it still round-trips with the new fields populated.
        let decoded = try WatchSnapshotCodec.decode(WatchSnapshotCodec.encode(synced))
        #expect(decoded == synced)
    }

    // MARK: - Watch receiving logic (local store)

    @Test("Store saves and loads the snapshot; empty store loads nil")
    func storeSaveLoad() throws {
        let store = tempStore()
        #expect(store.load() == nil)

        let snapshot = sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 10))
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("Receiving keeps the newest snapshot and ignores stale ones")
    func ingestKeepsNewest() {
        let store = tempStore()
        let older = sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 100))
        let newer = sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 200))

        #expect(store.ingest(older) == true)                                  // first stored
        #expect(store.ingest(newer) == true)                                  // newer replaces
        #expect(store.load()?.lastUpdated == Date(timeIntervalSince1970: 200))
        #expect(store.ingest(older) == false)                                 // stale ignored
        #expect(store.load()?.lastUpdated == Date(timeIntervalSince1970: 200))
    }

    // MARK: - Watch provider (no-data fallback + synced data)

    @Test("Watch shows the empty state when nothing has synced yet")
    func noDataFallback() async {
        let snapshot = await SyncedWatchSnapshotProvider(store: tempStore()).load()
        #expect(snapshot.hasData == false)
        #expect(snapshot.alerts.isEmpty)
    }

    @Test("Watch provider surfaces the synced snapshot")
    func providerExposesSyncedData() async throws {
        let store = tempStore()
        try store.save(sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 10)))

        let snapshot = await SyncedWatchSnapshotProvider(store: store).load()

        #expect(snapshot.hasData)
        #expect(snapshot.fleet.total == 5)
        #expect(snapshot.alerts.count == 1)
    }
}
