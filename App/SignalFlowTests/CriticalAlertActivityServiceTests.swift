import Foundation
import Testing
import ActivityKit
import DomainKit
import LiveActivityKit

/// Runs the real ``CriticalAlertActivityService`` against ActivityKit in the simulator.
///
/// The SwiftPM suite covers the lifecycle *decisions* on macOS, where ActivityKit doesn't exist and the
/// service is a no-op stub. These tests cover what only the iOS build does: requesting, adopting and
/// ending real activities. They need an app host because ActivityKit only serves an app whose
/// Info.plist declares `NSSupportsLiveActivities`; the host app stays idle under tests (see
/// `SignalFlowApp`), so the activities here are the only ones.
@Suite("Critical-alert Live Activity on iOS", .serialized)
struct CriticalAlertActivityServiceTests {
    private typealias CriticalActivity = Activity<CriticalAlertActivityAttributes>

    init() async throws {
        try #require(ActivityAuthorizationInfo().areActivitiesEnabled, "Live Activities are disabled on this simulator")
        await endEverything()
    }

    @Test("Starting shows one activity whose content goes stale after a minute")
    func startsWithStaleDate() async throws {
        let context = try critical()
        let before = Date.now
        await CriticalAlertActivityService().reconcile([context])

        let running = shown()
        try #require(running.count == 1)
        let activity = running[0]
        #expect(activity.attributes.alertID == context.alert.id.rawValue.uuidString)
        #expect(activity.attributes.deviceID == context.alert.deviceID.rawValue.uuidString)
        #expect(activity.content.state.status == .active)
        let staleDate = try #require(activity.content.staleDate)
        #expect(abs(staleDate.timeIntervalSince(before) - LiveActivityDecision.staleAfter) < 5)
        await endEverything()
    }

    @Test("A relaunched service takes over the running activity instead of starting another")
    func relaunchAdopts() async throws {
        let context = try critical()
        await CriticalAlertActivityService().reconcile([context])
        let original = try #require(shown().first?.id)

        // A new instance has no memory of the activity, like the service after the app is relaunched.
        await CriticalAlertActivityService().reconcile([context])

        #expect(shown().map(\.id) == [original])
        await endEverything()
    }

    @Test("A relaunched service ends duplicate activities and keeps the one for the live alert")
    func relaunchEndsDuplicates() async throws {
        let live = try critical(raisedAt: 200)
        let cleared = try critical(raisedAt: 100)
        // Two activities left running by an earlier launch; only `live` is still a critical alert.
        for context in [cleared, live] {
            let attributes = CriticalAlertActivityAttributes(
                alertID: context.alert.id.rawValue.uuidString,
                deviceID: context.alert.deviceID.rawValue.uuidString
            )
            let state = CriticalAlertState.make(context, status: .active)
            _ = try CriticalActivity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        }
        try #require(shown().count == 2)

        await CriticalAlertActivityService().reconcile([live])

        #expect(shown().map(\.attributes.alertID) == [live.alert.id.rawValue.uuidString])
        await endEverything()
    }

    @Test("Acknowledging the alert ends the activity on an Acknowledged frame")
    func acknowledgementEnds() async throws {
        let service = CriticalAlertActivityService()
        var context = try critical()
        await service.reconcile([context])
        let activity = try #require(shown().first)

        var acknowledged = context.alert
        try acknowledged.acknowledge(at: .now)
        context = AlertContext(alert: acknowledged, deviceName: context.deviceName, assetName: context.assetName)
        await service.reconcile([context])

        #expect(shown().isEmpty)
        #expect(activity.activityState == .ended)
        #expect(activity.content.state.status == .acknowledged)
        await endEverything()
    }

    // MARK: - Helpers

    /// Activities still on screen (ended ones linger until the system dismisses them).
    private func shown() -> [CriticalActivity] {
        CriticalActivity.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private func endEverything() async {
        for activity in CriticalActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func critical(raisedAt: TimeInterval = 100) throws -> AlertContext {
        let alert = Alert(
            deviceID: DeviceID(), ruleID: AlertRuleID(), metric: .temperature, severity: .critical,
            message: "Temperature above safe limit", observedValue: try MeasuredValue(magnitude: 12, unit: .celsius),
            raisedAt: Date(timeIntervalSince1970: raisedAt)
        )
        return AlertContext(alert: alert, deviceName: "Reefer 12", assetName: "Fleet A")
    }
}
