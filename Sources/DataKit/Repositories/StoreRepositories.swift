import Foundation
import DomainKit

/// The repositories are thin, `Sendable` adapters: they forward `DomainKit` port calls to the
/// `InMemoryTelemetryStore` actor. They contain no logic of their own, so the store stays the single
/// source of truth and features depend only on the abstract ports.

public struct StoreAssetRepository: AssetRepository {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func allAssets() async throws -> [Asset] { try await store.allAssets() }
    public func asset(_ id: AssetID) async throws -> Asset { try await store.asset(id) }
}

public struct StoreDeviceRepository: DeviceRepository {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func devices(inAsset assetID: AssetID) async throws -> [Device] {
        try await store.devices(inAsset: assetID)
    }
    public func device(_ id: DeviceID) async throws -> Device { try await store.device(id) }
}

public struct StoreTelemetryRepository: TelemetryRepository {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading] {
        try await store.latestReadings(forDevice: deviceID)
    }
    public func readings(forDevice deviceID: DeviceID, metric: MetricKind, in range: TimeRange) async throws -> [TelemetryReading] {
        try await store.readings(forDevice: deviceID, metric: metric, in: range)
    }
}

public struct StoreAlertRepository: AlertRepository {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func activeAlerts(forDevice deviceID: DeviceID) async throws -> [Alert] {
        try await store.activeAlerts(forDevice: deviceID)
    }
    public func rules(forDevice deviceID: DeviceID) async throws -> [AlertRule] {
        try await store.rules(forDevice: deviceID)
    }
    public func record(_ alert: Alert) async throws {
        await store.record(alert)
    }
    public func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {
        try await store.acknowledgeAlert(id, at: date)
    }
}

public struct StoreAlertHistoryRepository: AlertHistoryProviding {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func alertHistory(limit: Int) async throws -> [Alert] {
        await store.alertHistory(limit: limit)
    }
}

public struct StoreEventRepository: EventRepository {
    private let store: InMemoryTelemetryStore
    public init(store: InMemoryTelemetryStore) { self.store = store }

    public func recentEvents(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent] {
        try await store.recentEvents(forDevice: deviceID, limit: limit)
    }
    public func recentEvents(limit: Int) async throws -> [DeviceEvent] {
        await store.recentEvents(limit: limit)
    }
}
