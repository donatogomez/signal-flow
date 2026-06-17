import Foundation
import Testing
import DomainKit

@Suite("Entity creation & invariants")
struct EntityTests {

    @Test("Entities reject empty names")
    func entitiesRejectEmptyNames() {
        #expect(throws: ValidationError.self) { _ = try Asset(name: " ", kind: .greenhouse) }
        #expect(throws: ValidationError.self) { _ = try Device(assetID: AssetID(), name: "") }
        #expect(throws: ValidationError.self) {
            _ = try AlertRule(name: "", metric: .humidity, threshold: try Threshold(upperBound: 70), severity: .warning)
        }
    }

    @Test("Entities trim surrounding whitespace from names")
    func entitiesTrimNames() throws {
        let asset = try Asset(name: "  Greenhouse 3  ", kind: .greenhouse)
        #expect(asset.name == "Greenhouse 3")
    }

    @Test("Identifiers of different scopes are distinct types but compare by raw value")
    func identifierIdentity() {
        let raw = UUID()
        #expect(DeviceID(raw) == DeviceID(raw))
        #expect(DeviceID(raw).rawValue == raw)
        // AssetID(raw) and DeviceID(raw) cannot even be compared — the type system forbids it.
    }

    @Test("Alert acknowledgement is forward-only")
    func acknowledgementIsForwardOnly() throws {
        var alert = Alert(
            deviceID: DeviceID(),
            ruleID: AlertRuleID(),
            metric: .temperature,
            severity: .critical,
            message: "too hot",
            observedValue: try MeasuredValue(magnitude: 8, unit: .celsius),
            raisedAt: Fixtures.referenceDate
        )
        #expect(alert.isAcknowledged == false)

        try alert.acknowledge(at: Fixtures.referenceDate.addingTimeInterval(60))
        #expect(alert.isAcknowledged)

        #expect(throws: DomainError.alertAlreadyAcknowledged(alert.id)) {
            try alert.acknowledge(at: Fixtures.referenceDate.addingTimeInterval(120))
        }
    }

    @Test("Domain values round-trip through Codable")
    func codableRoundTrip() throws {
        let device = try Device(
            assetID: AssetID(),
            name: "Reefer 7",
            metrics: [try MetricDefinition(kind: .temperature, name: "Internal temp")],
            battery: try BatteryStatus(percentage: 64, isCharging: true),
            connectivity: ConnectivityStatus(state: .online),
            lastKnownLocation: try Location(latitude: 41.4, longitude: 2.1)
        )
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(Device.self, from: data)
        #expect(decoded == device)
    }
}
