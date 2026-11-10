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

// MARK: - Freshness and relaunch

extension LiveActivityDecision {
    /// How long pushed content counts as current. If the app stops reconciling (suspended or killed),
    /// the system marks the activity stale after this, and the card says so instead of presenting a
    /// frozen alert as live.
    public static let staleAfter: TimeInterval = 60

    /// While the app runs, unchanged content is pushed again this often, so it never goes stale.
    public static let refreshAfter: TimeInterval = 30

    /// Whether unchanged content last pushed at `pushedAt` (`nil`: never, as for an adopted activity)
    /// should be pushed again at `now` to stay fresh.
    public static func needsRefresh(pushedAt: Date?, now: Date) -> Bool {
        guard let pushedAt else { return true }
        return now.timeIntervalSince(pushedAt) >= refreshAfter
    }

    /// The running activity to take over after a relaunch, as an index into `runningAlertIDs`.
    ///
    /// ActivityKit keeps an activity running after the app ends, but the service starts with no memory
    /// of it and would otherwise start a duplicate. It takes over the activity for an alert that is
    /// still an active, unacknowledged critical, else the first one, which the next decision then ends
    /// with a final frame. Every other running activity is a duplicate to end. `nil` when none run.
    public static func adoptable(runningAlertIDs: [String], criticalContexts: [AlertContext]) -> Int? {
        let live = Set(criticalContexts.filter { !$0.alert.isAcknowledged }.map { $0.alert.id.rawValue.uuidString })
        return runningAlertIDs.firstIndex(where: live.contains) ?? runningAlertIDs.indices.first
    }
}
