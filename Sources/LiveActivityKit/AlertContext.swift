import Foundation
import DomainKit

/// A domain alert joined with its device/asset display context.
///
/// The app builds these from `DomainKit` ports (asset → device → active alerts) and hands them to the
/// selector/decision logic. Keeping it a plain value type means all of the Live Activity *logic* is
/// deterministic and testable without ActivityKit or any data-engine dependency.
public struct AlertContext: Sendable, Equatable {
    public let alert: Alert
    public let deviceName: String
    public let assetName: String?

    public init(alert: Alert, deviceName: String, assetName: String?) {
        self.alert = alert
        self.deviceName = deviceName
        self.assetName = assetName
    }
}

public enum CriticalAlertSelector {
    /// The **active critical** alerts among the given contexts, most-recent first.
    ///
    /// Acknowledged-but-not-yet-cleared criticals are intentionally *kept* here — the lifecycle decision
    /// uses their presence to drive the activity to its "Acknowledged" end state. Selection is purely a
    /// function of deterministic domain state (severity + raise time); AI is never consulted.
    public static func critical(in contexts: [AlertContext]) -> [AlertContext] {
        contexts
            .filter { $0.alert.severity == .critical }
            .sorted { $0.alert.raisedAt > $1.alert.raisedAt }
    }
}
