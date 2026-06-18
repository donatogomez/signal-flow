import Foundation
import Testing
import DomainKit
import DataKit
@testable import FeatureDeviceDetail

@MainActor
@Suite("Device detail model")
struct DeviceDetailModelTests {

    @Test("Loads telemetry, a temperature trend, alerts, and events")
    func loadsDetail() async throws {
        let device = try FX.device("Reefer 12", asset: AssetID(), connectivity: .online)

        let latest = [try FX.reading(device: device.id, .temperature, 4, unit: .celsius, at: 600)]
        let tempHistory = [
            try FX.reading(device: device.id, .temperature, 2, unit: .celsius, at: 0),
            try FX.reading(device: device.id, .temperature, 4, unit: .celsius, at: 300),
            try FX.reading(device: device.id, .temperature, 6, unit: .celsius, at: 600),
        ]

        let devices = FakeDeviceRepository(byID: [device.id: device])
        let telemetry = FakeTelemetryRepository(latest: [device.id: latest], history: [device.id: [.temperature: tempHistory]])
        let alerts = FakeAlertRepository(alertsByDevice: [device.id: [try FX.criticalAlert(device: device.id)]])
        let events = FakeEventRepository(events: [FX.event(device: device.id, .doorOpened, at: 10)])

        let model = DeviceDetailModel(deviceID: device.id, devices: devices, telemetry: telemetry, alerts: alerts, events: events)
        await model.refresh()

        #expect(model.phase == .loaded)
        #expect(model.deviceName == "Reefer 12")
        #expect(model.status == .critical)            // online + a critical alert
        #expect(model.readings.contains { $0.metric == .temperature })
        #expect(model.trends.contains { $0.metric == .temperature })
        #expect(model.alerts.count == 1)
        #expect(model.events.count == 1)
    }

    @Test("A metric with fewer than two points produces no trend")
    func noTrendWithoutEnoughPoints() async throws {
        let device = try FX.device("Reefer 12", asset: AssetID(), connectivity: .online)
        let telemetry = FakeTelemetryRepository(
            latest: [device.id: [try FX.reading(device: device.id, .temperature, 4, unit: .celsius, at: 0)]],
            history: [device.id: [.temperature: [try FX.reading(device: device.id, .temperature, 4, unit: .celsius, at: 0)]]]
        )
        let model = DeviceDetailModel(
            deviceID: device.id,
            devices: FakeDeviceRepository(byID: [device.id: device]),
            telemetry: telemetry,
            alerts: FakeAlertRepository(),
            events: FakeEventRepository()
        )
        await model.refresh()
        #expect(model.trends.isEmpty)
    }

    @Test("Integration: loads a real device through DataKit")
    func integrationWithDataKit() async throws {
        let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: 40)
        try await source.bootstrap()
        await source.ingestAll()
        let asset = try #require(try await source.assets.allAssets().first)
        let device = try #require(try await source.devices.devices(inAsset: asset.id).first)

        let model = DeviceDetailModel(
            deviceID: device.id,
            devices: source.devices, telemetry: source.telemetry, alerts: source.alerts, events: source.events
        )
        await model.refresh()
        #expect(model.phase == .loaded)
        #expect(!model.readings.isEmpty)
        #expect(model.trends.contains { $0.metric == .temperature })
    }
}
