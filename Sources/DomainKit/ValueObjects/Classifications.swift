/// Severity of an alert, ordered from least to most urgent.
///
/// `Comparable` lets callers pick the worst severity in a set with `max()`.
public enum AlertSeverity: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// The kind of physical asset being monitored.
public enum AssetKind: String, Codable, Hashable, Sendable, CaseIterable {
    case greenhouse
    case refrigeratedTruck
    case coldChainContainer
    case warehouse
    case industrialEquipment
    case environmentalStation

    public var displayName: String {
        switch self {
        case .greenhouse: "Greenhouse"
        case .refrigeratedTruck: "Refrigerated truck"
        case .coldChainContainer: "Cold-chain container"
        case .warehouse: "Warehouse"
        case .industrialEquipment: "Industrial equipment"
        case .environmentalStation: "Environmental station"
        }
    }
}

/// A device's overall health rollup, derived (never stored) from connectivity and active alerts.
///
/// - SeeAlso: ``DeviceHealthPolicy``
public enum DeviceStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case nominal
    case warning
    case critical
    case offline
}
