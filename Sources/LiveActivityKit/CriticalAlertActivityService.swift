import Foundation
import DomainKit

#if os(iOS)
import ActivityKit

/// Drives the critical-alert Live Activity: it reconciles the current critical-alert state against the
/// running activity, applying the pure ``LiveActivityDecision``. ActivityKit calls live only here, so
/// they never leak into features (which don't even link this module).
///
/// An `actor` so the tracked state and the `Activity` handle are mutated race-free; reconciliation is
/// safe to call from a polling loop in the composition root.
public actor CriticalAlertActivityService {
    private var tracked: TrackedActivity?
    /// We store only the running activity's **id** (a `Sendable` `String`), never the `Activity` value
    /// itself — keeping a non-`Sendable` `Activity` in actor storage and awaiting on it trips Swift 6's
    /// region isolation ("sending actor-isolated state"). Instead we look the activity up locally from
    /// `Activity.activities` (a disconnected region) when we need to update or end it.
    private var activityID: String?

    public init() {}

    /// Reconciles the running activity with the latest alert contexts (built deterministically from
    /// domain ports). Starts, updates, or ends the activity as the lifecycle rules dictate.
    public func reconcile(_ contexts: [AlertContext]) async {
        let criticals = CriticalAlertSelector.critical(in: contexts)
        switch LiveActivityDecision.decide(tracked: tracked, criticalContexts: criticals) {
        case .none:
            break
        case .start(let next):
            await start(next)
        case .update(let state):
            await update(state)
        case .end(let finalState):
            await end(finalState)
        }
    }

    /// Ends every running critical-alert activity immediately (e.g. on teardown). Idempotent.
    public func endAll() async {
        for activity in Activity<CriticalAlertActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activityID = nil
        tracked = nil
    }

    // MARK: - ActivityKit operations

    private func start(_ next: TrackedActivity) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CriticalAlertActivityAttributes(alertID: next.alertID, deviceID: next.deviceID.rawValue.uuidString)
        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: next.state, staleDate: nil))
            activityID = activity.id
            tracked = next
        } catch {
            // Authorization revoked or system limit reached — nothing to surface to the user.
            activityID = nil
            tracked = nil
        }
    }

    private func update(_ state: CriticalAlertState) async {
        // The lookup is inlined (not extracted to a method) so `activity` stays in a *disconnected*
        // region and can be sent into the `await` without tripping region isolation.
        guard let current = tracked, let id = activityID,
              let activity = Activity<CriticalAlertActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        tracked = TrackedActivity(alertID: current.alertID, deviceID: current.deviceID, state: state)
    }

    private func end(_ finalState: CriticalAlertState) async {
        defer { activityID = nil; tracked = nil }
        guard let id = activityID,
              let activity = Activity<CriticalAlertActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        // Show the final "Acknowledged"/"Resolved" frame briefly, then let the system dismiss it.
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(8)))
    }
}

#else

/// Non-iOS stub (e.g. the macOS host that runs CI). ActivityKit is unavailable, so reconciliation is a
/// no-op — the composition root can call it unconditionally without `#if` at every call site.
public actor CriticalAlertActivityService {
    public init() {}
    public func reconcile(_ contexts: [AlertContext]) async {}
    public func endAll() async {}
}

#endif
