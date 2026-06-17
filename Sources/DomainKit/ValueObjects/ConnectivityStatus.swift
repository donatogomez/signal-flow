import Foundation

/// A device's link state, optionally annotated with the last seen time and signal strength.
public struct ConnectivityStatus: Hashable, Sendable, Codable {
    public enum State: String, Codable, Hashable, Sendable, CaseIterable {
        case online
        case degraded
        case offline
    }

    public let state: State
    public let signalStrength: MeasuredValue?
    public let lastSeenAt: Date?

    public init(state: State, signalStrength: MeasuredValue? = nil, lastSeenAt: Date? = nil) {
        self.state = state
        self.signalStrength = signalStrength
        self.lastSeenAt = lastSeenAt
    }

    public static let offline = ConnectivityStatus(state: .offline)
}
