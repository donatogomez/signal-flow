import Foundation
import DomainKit

/// The activity the service is currently showing: the alert's identity, the device it concerns (for
/// deep-linking), and the last content state pushed (for change detection).
public struct TrackedActivity: Equatable, Sendable {
    public let alertID: String
    public let deviceID: DeviceID
    public let state: CriticalAlertState

    public init(alertID: String, deviceID: DeviceID, state: CriticalAlertState) {
        self.alertID = alertID
        self.deviceID = deviceID
        self.state = state
    }
}

/// What the service should do this reconcile tick.
public enum LiveActivityAction: Equatable, Sendable {
    case none
    case start(TrackedActivity)
    case update(CriticalAlertState)
    case end(CriticalAlertState)
}

/// The pure lifecycle brain — no ActivityKit, no I/O, fully deterministic and unit-tested.
///
/// ## Lifecycle rules (documented in docs/26-live-activities.md)
/// - **Start** when no activity is running and there is an active, *unacknowledged* critical alert.
/// - **Update** when the tracked alert is still active+unacknowledged but its content changed.
/// - **End** when the tracked alert is **acknowledged** (a human saw it) *or* **resolved** (the
///   condition cleared and the alert is no longer active). The end carries a final state so the UI can
///   show "Acknowledged"/"Resolved" briefly before dismissal.
///
/// Ending on acknowledgement mirrors the rest of the app: `DeviceHealthPolicy` already stops counting
/// acknowledged alerts toward device health, so an acknowledged alert is no longer an *ongoing* crisis
/// worth a persistent Live Activity.
public enum LiveActivityDecision {
    public static func decide(tracked: TrackedActivity?, criticalContexts: [AlertContext]) -> LiveActivityAction {
        if let tracked {
            guard let current = criticalContexts.first(where: { $0.alert.id.rawValue.uuidString == tracked.alertID }) else {
                // The tracked alert is no longer among active criticals → it cleared.
                return .end(tracked.state.with(status: .resolved))
            }
            if current.alert.isAcknowledged {
                return .end(CriticalAlertState.make(current, status: .acknowledged))
            }
            let refreshed = CriticalAlertState.make(current, status: .active)
            return refreshed == tracked.state ? .none : .update(refreshed)
        }

        // No activity running: start one for the most recent active, unacknowledged critical alert.
        guard let top = criticalContexts.first(where: { !$0.alert.isAcknowledged }) else { return .none }
        return .start(
            TrackedActivity(
                alertID: top.alert.id.rawValue.uuidString,
                deviceID: top.alert.deviceID,
                state: CriticalAlertState.make(top, status: .active)
            )
        )
    }
}
