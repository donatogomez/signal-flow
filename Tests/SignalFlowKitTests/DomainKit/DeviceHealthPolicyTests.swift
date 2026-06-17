import Foundation
import Testing
import DomainKit

@Suite("Device health policy")
struct DeviceHealthPolicyTests {

    private func alert(_ severity: AlertSeverity, acknowledged: Bool = false) throws -> Alert {
        var alert = Alert(
            deviceID: DeviceID(),
            ruleID: AlertRuleID(),
            metric: .temperature,
            severity: severity,
            message: "test",
            observedValue: try MeasuredValue(magnitude: 1, unit: .celsius),
            raisedAt: Fixtures.referenceDate
        )
        if acknowledged { try alert.acknowledge(at: Fixtures.referenceDate.addingTimeInterval(1)) }
        return alert
    }

    @Test("Offline connectivity always yields offline status")
    func offlineWins() throws {
        let status = DeviceHealthPolicy.status(
            connectivity: .offline,
            activeAlerts: [try alert(.critical)]
        )
        #expect(status == .offline)
    }

    @Test("Online with no alerts is nominal")
    func onlineNominal() {
        let status = DeviceHealthPolicy.status(
            connectivity: ConnectivityStatus(state: .online),
            activeAlerts: []
        )
        #expect(status == .nominal)
    }

    @Test("Degraded connectivity with no alerts is a warning")
    func degradedWarns() {
        let status = DeviceHealthPolicy.status(
            connectivity: ConnectivityStatus(state: .degraded),
            activeAlerts: []
        )
        #expect(status == .warning)
    }

    @Test("Status reflects the worst unacknowledged alert")
    func worstSeverityWins() throws {
        let status = DeviceHealthPolicy.status(
            connectivity: ConnectivityStatus(state: .online),
            activeAlerts: [try alert(.warning), try alert(.critical), try alert(.info)]
        )
        #expect(status == .critical)
    }

    @Test("Acknowledged alerts do not drive status")
    func acknowledgedIgnored() throws {
        let status = DeviceHealthPolicy.status(
            connectivity: ConnectivityStatus(state: .online),
            activeAlerts: [try alert(.critical, acknowledged: true)]
        )
        #expect(status == .nominal)
    }
}
