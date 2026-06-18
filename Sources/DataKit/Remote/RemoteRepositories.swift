import Foundation
import DomainKit
import NetworkingKit

/// `DomainKit` repository adapters backed by a `NetworkingKit` ``RemoteGateway``.
///
/// They delegate straight to the gateway (which already returns domain entities), so DataKit's
/// orchestration is unchanged and features still depend only on the ports. This is the remote-backed
/// alternative to the simulated/store-backed repositories, ready to be selected at the composition
/// root.

struct RemoteAssetRepository: AssetRepository {
    let gateway: any RemoteGateway
    func allAssets() async throws -> [Asset] { try await gateway.assets() }
    func asset(_ id: AssetID) async throws -> Asset {
        guard let asset = try await gateway.assets().first(where: { $0.id == id }) else {
            throw DomainError.assetNotFound(id)
        }
        return asset
    }
}

struct RemoteDeviceRepository: DeviceRepository {
    let gateway: any RemoteGateway
    func devices(inAsset assetID: AssetID) async throws -> [Device] { try await gateway.devices(inAsset: assetID) }
    func device(_ id: DeviceID) async throws -> Device { try await gateway.device(id) }
}

struct RemoteTelemetryRepository: TelemetryRepository {
    let gateway: any RemoteGateway
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading] {
        try await gateway.latestReadings(forDevice: deviceID)
    }
    func readings(forDevice deviceID: DeviceID, metric: MetricKind, in range: TimeRange) async throws -> [TelemetryReading] {
        try await gateway.telemetry(forDevice: deviceID, metric: metric, in: range)
    }
}

struct RemoteEventRepository: EventRepository {
    let gateway: any RemoteGateway
    func recentEvents(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent] {
        try await gateway.events(forDevice: deviceID, limit: limit)
    }
    func recentEvents(limit: Int) async throws -> [DeviceEvent] {
        // Fleet-wide aggregation. A real backend would expose a single fleet-events endpoint; this
        // composes the per-device one, which is fine for the scaffold.
        var all: [DeviceEvent] = []
        for asset in try await gateway.assets() {
            for device in try await gateway.devices(inAsset: asset.id) {
                all += try await gateway.events(forDevice: device.id, limit: limit)
            }
        }
        return Array(all.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }
}

struct RemoteAlertRepository: AlertRepository {
    let gateway: any RemoteGateway
    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert] {
        try await gateway.alerts(forDevice: deviceID)
    }
    /// Alert rules are evaluated server-side, so a remote client doesn't own them.
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule] { [] }
    /// Alerts are server-raised; the client doesn't push them.
    func record(_ alert: Alert) async throws {}
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {
        try await gateway.acknowledgeAlert(id, at: date)
    }
}
