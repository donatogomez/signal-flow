import Foundation
import Testing
import DomainKit
@testable import NetworkingKit

@Suite("DTO → Domain mapping")
struct DTOMappingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    @Test("Asset decodes and maps, including location")
    func asset() throws {
        let dto = try decode([AssetDTO].self, NetFixtures.assetsJSON)[0]
        let asset = try DTOMapping.asset(dto)
        #expect(asset.id.rawValue.uuidString == NetFixtures.assetID.uppercased())
        #expect(asset.kind == .greenhouse)
        #expect(asset.location?.latitude == 41.4)
        #expect(asset.deviceIDs.count == 1)
    }

    @Test("Device maps connectivity and signal strength")
    func device() throws {
        let dto = try decode(DeviceDTO.self, NetFixtures.deviceJSON)
        let device = try DTOMapping.device(dto)
        #expect(device.connectivity.state == .online)
        #expect(device.connectivity.signalStrength?.unit == .decibelMilliwatts)
        #expect(device.connectivity.signalStrength?.magnitude == -72)
    }

    @Test("Reading maps unit-aware values")
    func reading() throws {
        let dto = try decode([TelemetryReadingDTO].self, NetFixtures.telemetryJSON)[0]
        let reading = try DTOMapping.reading(dto)
        #expect(reading.metric == .temperature)
        #expect(reading.value.magnitude == 3.5)
        #expect(reading.value.unit == .celsius)
    }

    @Test("A custom metric key maps to .custom")
    func customMetric() {
        #expect(DTOMapping.metricKind("custom:pressure") == .custom("pressure"))
        #expect(DTOMapping.metricKind("temperature") == .temperature)
    }

    @Test("Alert maps acknowledgement state and severity")
    func alert() throws {
        let dto = try decode([AlertDTO].self, NetFixtures.alertsJSON)[0]
        let alert = try DTOMapping.alert(dto)
        #expect(alert.severity == .critical)
        #expect(alert.isAcknowledged == false)
        #expect(alert.observedValue.magnitude == 12)
    }

    @Test("An invalid UUID is rejected")
    func invalidUUID() {
        let dto = AssetDTO(id: "not-a-uuid", name: "x", kind: "warehouse", deviceIds: [], location: nil)
        #expect(throws: (any Error).self) { _ = try DTOMapping.asset(dto) }
    }
}
