/// The qualitative direction of a metric over a window — a *grounded fact* computed in Swift from
/// readings, never decided by a model.
public enum TrendDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case rising
    case falling
    case stable
    case volatile

    public var label: String {
        switch self {
        case .rising: "rising"
        case .falling: "falling"
        case .stable: "holding steady"
        case .volatile: "volatile"
        }
    }
}
