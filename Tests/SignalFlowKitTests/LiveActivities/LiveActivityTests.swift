import Testing
import Foundation
import DomainKit
import SnapshotKit
@testable import LiveActivityKit

@Suite("Live Activities")
struct LiveActivityTests {

    // MARK: - Builders

    private func alert(
        _ severity: AlertSeverity,
        device: DeviceID = DeviceID(),
        id: AlertID = AlertID(),
        raisedAt: TimeInterval = 1,
        acknowledged: Bool = false,
        message: String = "Temperature above safe limit"
    ) throws -> Alert {
        var alert = Alert(
            id: id, deviceID: device, ruleID: AlertRuleID(), metric: .temperature, severity: severity,
            message: message, observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: raisedAt)
        )
        if acknowledged { try alert.acknowledge(at: Date(timeIntervalSince1970: raisedAt + 1)) }
        return alert
    }

    private func ctx(_ alert: Alert, device: String = "Reefer 12", asset: String? = "Fleet A") -> AlertContext {
        AlertContext(alert: alert, deviceName: device, assetName: asset)
    }

    private func tracked(for alert: Alert, status: AlertActivityStatus = .active) -> TrackedActivity {
        TrackedActivity(
            alertID: alert.id.rawValue.uuidString,
            deviceID: alert.deviceID,
            state: CriticalAlertState.make(ctx(alert), status: status)
        )
    }

    // MARK: - Activity state mapping

    @Test("Maps a domain alert + context into activity content")
    func stateMapping() throws {
        let a = try alert(.critical, raisedAt: 100, message: "Temperature above safe limit")
        let state = CriticalAlertState.make(ctx(a, device: "Reefer 12", asset: "Fleet A"), status: .active)

        #expect(state.deviceName == "Reefer 12")
        #expect(state.assetName == "Fleet A")
        #expect(state.severity == .critical)
        #expect(state.reason == "Temperature above safe limit")
        #expect(state.startedAt == Date(timeIntervalSince1970: 100))
        #expect(state.status == .active)
        #expect(state.with(status: .resolved).status == .resolved)
    }

    // MARK: - Critical alert selection

    @Test("Selects only active critical alerts, most recent first")
    func criticalSelection() throws {
        let older = ctx(try alert(.critical, raisedAt: 10))
        let newer = ctx(try alert(.critical, raisedAt: 50))
        let warning = ctx(try alert(.warning, raisedAt: 99))

        let selected = CriticalAlertSelector.critical(in: [older, warning, newer])

        #expect(selected.count == 2)
        #expect(selected.first?.alert.raisedAt == Date(timeIntervalSince1970: 50))
    }

    @Test("No activity for non-critical alerts")
    func noActivityForNonCritical() throws {
        let contexts = [ctx(try alert(.warning)), ctx(try alert(.info))]

        #expect(CriticalAlertSelector.critical(in: contexts).isEmpty)
        #expect(LiveActivityDecision.decide(tracked: nil, criticalContexts: CriticalAlertSelector.critical(in: contexts)) == .none)
    }

    // MARK: - Lifecycle decision logic

    @Test("Starts an activity for an unacknowledged critical alert")
    func lifecycleStart() throws {
        let device = DeviceID(), id = AlertID()
        let context = ctx(try alert(.critical, device: device, id: id, raisedAt: 5))

        guard case .start(let next) = LiveActivityDecision.decide(tracked: nil, criticalContexts: [context]) else {
            Issue.record("expected .start"); return
        }
        #expect(next.alertID == id.rawValue.uuidString)
        #expect(next.deviceID == device)
        #expect(next.state.status == .active)
    }

    @Test("Does not start for an already-acknowledged critical alert")
    func lifecycleNoStartWhenAcknowledged() throws {
        let acked = ctx(try alert(.critical, acknowledged: true))
        #expect(LiveActivityDecision.decide(tracked: nil, criticalContexts: [acked]) == .none)
    }

    @Test("Updates when the tracked alert's content changes")
    func lifecycleUpdate() throws {
        let device = DeviceID(), id = AlertID()
        let original = try alert(.critical, device: device, id: id, raisedAt: 5, message: "Old reason")
        let changed = try alert(.critical, device: device, id: id, raisedAt: 5, message: "New reason")

        guard case .update(let state) = LiveActivityDecision.decide(tracked: tracked(for: original), criticalContexts: [ctx(changed)]) else {
            Issue.record("expected .update"); return
        }
        #expect(state.reason == "New reason")
        #expect(state.status == .active)
    }

    @Test("No action when the tracked alert is unchanged")
    func lifecycleNoChange() throws {
        let device = DeviceID(), id = AlertID()
        let a = try alert(.critical, device: device, id: id, raisedAt: 5)
        #expect(LiveActivityDecision.decide(tracked: tracked(for: a), criticalContexts: [ctx(a)]) == .none)
    }

    @Test("Ends (acknowledged) when the tracked alert is acknowledged")
    func lifecycleEndOnAcknowledge() throws {
        let device = DeviceID(), id = AlertID()
        let active = try alert(.critical, device: device, id: id, raisedAt: 5)
        let acked = try alert(.critical, device: device, id: id, raisedAt: 5, acknowledged: true)

        guard case .end(let state) = LiveActivityDecision.decide(tracked: tracked(for: active), criticalContexts: [ctx(acked)]) else {
            Issue.record("expected .end"); return
        }
        #expect(state.status == .acknowledged)
    }

    @Test("Ends (resolved) when the tracked alert is no longer active")
    func lifecycleEndOnResolve() throws {
        let active = try alert(.critical, raisedAt: 5)

        guard case .end(let state) = LiveActivityDecision.decide(tracked: tracked(for: active), criticalContexts: []) else {
            Issue.record("expected .end"); return
        }
        #expect(state.status == .resolved)
    }

    // MARK: - Deep-link route generation

    @Test("Deep links generate and round-trip for tabs and devices")
    func deepLinkGeneration() {
        #expect(DeepLink.route(.alerts).url.absoluteString == "signalflow://alerts")

        let device = DeviceID()
        let url = DeepLink.device(device).url
        #expect(url.absoluteString == "signalflow://device/\(device.rawValue.uuidString)")
        #expect(DeepLink(url: url) == .device(device))

        #expect(DeepLink(url: DeepLinkRoute.alerts.url) == .route(.alerts))
        #expect(DeepLink(url: URL(string: "signalflow://device/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "https://example.com")!) == nil)
    }
}
