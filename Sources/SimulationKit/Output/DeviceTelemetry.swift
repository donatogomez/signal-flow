import Foundation
import DomainKit

/// One item emitted by a simulated device: a metric reading, a discrete event, or a position update.
///
/// Everything here is a `DomainKit` value type, so the future Dashboard, Charts, Alerts, and
/// Foundation Models features consume the simulation through the same domain vocabulary they'll use
/// for live data — the simulator is indistinguishable from a real source downstream.
public enum DeviceTelemetry: Sendable, Hashable {
    case reading(TelemetryReading)
    case event(DeviceEvent)
    case location(deviceID: DeviceID, location: Location, recordedAt: Date)

    public var deviceID: DeviceID {
        switch self {
        case .reading(let reading): reading.deviceID
        case .event(let event): event.deviceID
        case .location(let deviceID, _, _): deviceID
        }
    }

    public var timestamp: Date {
        switch self {
        case .reading(let reading): reading.recordedAt
        case .event(let event): event.occurredAt
        case .location(_, _, let recordedAt): recordedAt
        }
    }
}

/// Lightweight, `Sendable` identity for a simulated device — lets the engine surface its fleet without
/// crossing into each device actor's isolation.
public struct DeviceDescriptor: Sendable, Hashable {
    public let id: DeviceID
    public let assetID: AssetID
    public let name: String
    public let assetKind: AssetKind

    public init(id: DeviceID, assetID: AssetID, name: String, assetKind: AssetKind) {
        self.id = id
        self.assetID = assetID
        self.name = name
        self.assetKind = assetKind
    }
}
