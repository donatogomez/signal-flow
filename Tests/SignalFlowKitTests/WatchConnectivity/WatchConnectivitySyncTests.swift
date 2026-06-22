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
            criticalAlerts: [WidgetAlert(id: AlertID(), deviceName: "D1", severity: .critical, message: "m", raisedAt: Date(timeIntervalSince1970: 1))],
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
