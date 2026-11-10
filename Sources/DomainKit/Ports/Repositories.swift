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

/// Access to telemetry: the latest snapshot per metric, ranged history for charts, and the newest few
/// readings of a metric for short trends.
public protocol TelemetryRepository: Sendable {
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading]
    func readings(
        forDevice deviceID: DeviceID,
        metric: MetricKind,
        in range: TimeRange
    ) async throws -> [TelemetryReading]
    /// The newest `limit` readings of one metric by `recordedAt`, oldest-first. Empty when `limit` is
    /// not positive.
    func recentReadings(
        forDevice deviceID: DeviceID,
        metric: MetricKind,
        limit: Int
    ) async throws -> [TelemetryReading]
}

extension TelemetryRepository {
    /// Reads the whole history and keeps its newest `limit` readings. Correct for any repository;
    /// one that can answer without materializing the history should implement it.
    public func recentReadings(
        forDevice deviceID: DeviceID,
        metric: MetricKind,
        limit: Int
    ) async throws -> [TelemetryReading] {
        guard limit > 0 else { return [] }
        let everything = try TimeRange(start: .distantPast, end: .distantFuture)
        return Array(try await readings(forDevice: deviceID, metric: metric, in: everything)
            .sorted { $0.recordedAt < $1.recordedAt }
            .suffix(limit))
    }
}

/// Access to alerts and the rules that raise them.
public protocol AlertRepository: Sendable {
    func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert]
    func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule]
    func record(_ alert: Alert) async throws
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws
}
