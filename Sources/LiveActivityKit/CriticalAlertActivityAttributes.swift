#if os(iOS)
import Foundation
import ActivityKit
import DomainKit
import SnapshotKit

/// The ActivityKit attributes for a critical-alert Live Activity.
///
/// **Static** identity lives here (the alert id and the device it concerns); the **dynamic** content is
/// ``CriticalAlertState`` (the `ContentState`). Guarded by `#if os(iOS)` because ActivityKit's types are
/// unavailable on the macOS host that runs `swift build`/`swift test` — the testable logic lives in the
/// platform-agnostic files alongside this one.
public struct CriticalAlertActivityAttributes: ActivityAttributes {
    public typealias ContentState = CriticalAlertState

    public let alertID: String
    public let deviceID: String

    public init(alertID: String, deviceID: String) {
        self.alertID = alertID
        self.deviceID = deviceID
    }

    /// Where a tap should land: the device's detail screen when the id is valid, else the Alerts tab.
    public var deepLink: DeepLink {
        if let uuid = UUID(uuidString: deviceID) {
            return .device(DeviceID(uuid))
        }
        return .route(.alerts)
    }
}
#endif
