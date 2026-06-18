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
}

/// A render-ready recent-event row. Carries the domain `kind` (the view maps it to a label/icon/tint
/// via DesignSystemKit) plus the resolved device name for context.
public struct EventRow: Identifiable, Sendable, Hashable {
    public let id: EventID
    public let kind: DeviceEvent.Kind
    public let deviceName: String
    public let occurredAt: Date
}
