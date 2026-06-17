import Foundation

/// Read access to the asset catalog.
///
/// Ports are owned by the Domain and implemented by outer layers (Dependency Inversion). They are
/// `Sendable` because implementations are actors that cross isolation boundaries.
public protocol AssetRepository: Sendable {
    func allAssets() async throws -> [Asset]
    func asset(_ id: AssetID) async throws -> Asset
}

/// Read access to devices.
public protocol DeviceRepository: Sendable {
    func devices(inAsset assetID: AssetID) async throws -> [Device]
    func device(_ id: DeviceID) async throws -> Device
}

/// Access to telemetry: the latest snapshot per metric and ranged history for charts.
public protocol TelemetryRepository: Sendable {
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading]
    func readings(
        forDevice deviceID: DeviceID,
        metric: MetricKind,
        in range: TimeRange
    ) async throws -> [TelemetryReading]
}

/// Access to alerts and the rules that raise them.
public protocol AlertRepository: Sendable {
    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert]
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule]
    func record(_ alert: Alert) async throws
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws
}
