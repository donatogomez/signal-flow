import Foundation
import DomainKit

/// Aggregated fleet figures shown on the dashboard. A plain value type so it's trivially `Equatable`
/// (the view only re-renders when a number actually changes).
public struct FleetStats: Sendable, Equatable {
    public var assetCount = 0
    public var totalDevices = 0
    public var online = 0
    public var offline = 0
    public var activeAlerts = 0
    public var nominal = 0
    public var warning = 0
    public var critical = 0

    public static let empty = FleetStats()

    /// Share of the fleet that is fully healthy (nominal), 0…1 — the gauge's fill. 0 when the fleet is empty.
    public var healthFraction: Double {
        totalDevices > 0 ? Double(nominal) / Double(totalDevices) : 0
    }

    /// A coarse health band for the gauge's colour + word. Bands are deliberately wide so the headline is
    /// stable — a single device flipping status doesn't change the word.
    public var healthBand: HealthBand {
        guard totalDevices > 0 else { return .unknown }
        switch healthFraction {
        case 0.8...: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .attention
        default: return .critical
        }
    }
}

/// The qualitative health word shown beside the gauge. Pure presentation; the view maps it to a semantic
/// colour and a localized label.
public enum HealthBand: Sendable, Equatable {
    case excellent, good, attention, critical, unknown
}

/// A render-ready recent-event row. Carries the domain `kind` (the view maps it to a label/icon/tint
/// via DesignSystemKit) plus the resolved device name for context.
public struct EventRow: Identifiable, Sendable, Hashable {
    public let id: EventID
    public let kind: DeviceEvent.Kind
    public let deviceName: String
    public let occurredAt: Date
}
