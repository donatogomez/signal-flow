import Foundation
import Testing
import DomainKit
import NetworkingKit
import DataKit

@Suite("Remote-backed data source")
struct RemoteDataSourceTests {

    private func source(_ json: Data) -> RemoteDataSource {
        RemoteDataSource(baseURL: NetFixtures.baseURL, transport: StubHTTPClient(json: json))
    }

    @Test("Asset repository serves mapped domain assets from the remote")
    func assets() async throws {
        let assets = try await source(NetFixtures.assetsJSON).assets.allAssets()
        #expect(assets.count == 1)
        #expect(assets.first?.name == "Greenhouse A")
    }

    @Test("Device repository serves mapped domain devices")
    func devices() async throws {
        let devices = try await source(NetFixtures.devicesJSON).devices.devices(inAsset: AssetID())
        #expect(devices.first?.connectivity.state == .online)
    }

    @Test("Telemetry repository serves mapped readings")
    func telemetry() async throws {
        let range = try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1000))
        let readings = try await source(NetFixtures.telemetryJSON).telemetry.readings(forDevice: DeviceID(), metric: .temperature, in: range)
        #expect(readings.first?.value.magnitude == 3.5)
    }

    @Test("Alert repository serves mapped active alerts")
    func alerts() async throws {
        let alerts = try await source(NetFixtures.alertsJSON).alerts.activeAlerts(forDevice: DeviceID())
        #expect(alerts.first?.severity == .critical)
    }

    @Test("A remote alert repository acknowledges via the gateway without error")
    func acknowledge() async throws {
        let src = RemoteDataSource(baseURL: NetFixtures.baseURL, transport: StubHTTPClient([.status(204)]))
        try await src.alerts.acknowledgeAlert(AlertID(), at: Date())
    }
}
