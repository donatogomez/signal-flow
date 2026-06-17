import Foundation

/// A discrete, timestamped event reported by a device (as opposed to a continuous reading).
public struct DeviceEvent: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case doorOpened
        case doorClosed
        case connected
        case disconnected
        case powerLost
        case powerRestored
        case custom(String)
    }

    public let id: EventID
    public let deviceID: DeviceID
    public let kind: Kind
    public let occurredAt: Date
    public let detail: String?

    public init(
        id: EventID = EventID(),
        deviceID: DeviceID,
        kind: Kind,
        occurredAt: Date,
        detail: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.kind = kind
        self.occurredAt = occurredAt
        self.detail = detail
    }
}
