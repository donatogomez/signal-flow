import Foundation
import Testing
import DomainKit
@testable import PersistenceKit

@Suite("Persistence mapping round-trips")
struct MappingTests {

    @Test("Asset survives domain → record → domain")
    func assetRoundTrip() throws {
        let assetID = AssetID()
        let original = try PX.asset("Greenhouse A", kind: .greenhouse, id: assetID, devices: [DeviceID(), DeviceID()])
        let restored = try Mapping.asset(Mapping.record(original))
        #expect(restored == original)
    }

    @Test("Device survives the round-trip (last-known state preserved)")
    func deviceRoundTrip() throws {
        let original = try PX.device("Reefer 12", state: .degraded)
        let restored = try Mapping.device(Mapping.record(original))
        #expect(restored.id == original.id)
        #expect(restored.assetID == original.assetID)
        #expect(restored.connectivity.state == .degraded)
        #expect(restored.connectivity.signalStrength == original.connectivity.signalStrength)
        #expect(restored.lastKnownLocation == original.lastKnownLocation)
    }

    @Test("Reading survives the round-trip, including a custom metric")
    func readingRoundTrip() throws {
        let deviceID = DeviceID()
        let original = try PX.reading(device: deviceID, .custom("pressure"), 1013, unit: .hectopascals, at: 100)
        let restored = try Mapping.reading(Mapping.record(original))
        #expect(restored == original)
        #expect(restored.metric == .custom("pressure"))
    }

    @Test("Event survives the round-trip, including a custom kind")
    func eventRoundTrip() throws {
        let original = PX.event(device: DeviceID(), .custom("threshold_exceeded"), at: 50, detail: "temp 9.1")
        let restored = try Mapping.event(Mapping.record(original))
        #expect(restored == original)
    }

    @Test("Alert survives the round-trip with acknowledgement state")
    func alertRoundTrip() throws {
        let original = try PX.alert(device: DeviceID(), severity: .critical, acknowledged: true)
        let restored = try Mapping.alert(Mapping.record(original))
        #expect(restored == original)
        #expect(restored.isAcknowledged)
    }

    @Test("Insight record survives the round-trip")
    func insightRoundTrip() throws {
        let original = PX.insightRecord(device: DeviceID())
        let restored = try Mapping.insight(Mapping.record(original))
        #expect(restored == original)
    }
}
