import Foundation
import DomainKit
import SnapshotKit

/// Where a critical alert is in its lifecycle, as shown on the Live Activity.
public enum AlertActivityStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case active        // unacknowledged and ongoing
    case acknowledged  // a human has seen it (shown briefly, then the activity ends)
    case resolved      // the underlying condition cleared (shown briefly, then the activity ends)

    public var label: String {
        switch self {
        case .active: String(localized: "Active", bundle: .module)
        case .acknowledged: String(localized: "Acknowledged", bundle: .module)
        case .resolved: String(localized: "Resolved", bundle: .module)
        }
    }
}

/// The **dynamic** content of a critical-alert Live Activity — the part that changes over the
/// activity's life. This is a plain value type (no ActivityKit), so it compiles on every platform and
/// is unit-testable on the macOS host; on iOS it's used as `CriticalAlertActivityAttributes.ContentState`.
public struct CriticalAlertState: Codable, Hashable, Sendable {
    public var deviceName: String
    public var assetName: String?
    public var severity: AlertSeverity
    /// The alert's title/reason (its message).
    public var reason: String
    public var startedAt: Date
    public var status: AlertActivityStatus

    public init(
        deviceName: String,
        assetName: String?,
        severity: AlertSeverity,
        reason: String,
        startedAt: Date,
        status: AlertActivityStatus
    ) {
        self.deviceName = deviceName
        self.assetName = assetName
        self.severity = severity
        self.reason = reason
        self.startedAt = startedAt
        self.status = status
    }

    /// Maps a domain alert (+ its joined device/asset context) into activity content at a given status.
    public static func make(_ context: AlertContext, status: AlertActivityStatus) -> CriticalAlertState {
        CriticalAlertState(
            deviceName: context.deviceName,
            assetName: context.assetName,
            severity: context.alert.severity,
            reason: AlertText.message(metric: context.alert.metric, value: context.alert.observedValue),
            startedAt: context.alert.raisedAt,
            status: status
        )
    }

    /// A copy with a new status — used to show a final "Acknowledged"/"Resolved" frame before ending.
    public func with(status: AlertActivityStatus) -> CriticalAlertState {
        var copy = self
        copy.status = status
        return copy
    }
}
