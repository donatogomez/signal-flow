import Foundation
import DomainKit
import SimulationKit
import PersistenceKit

/// Mirrors the live telemetry stream into durable storage, off the hot path.
///
/// It buffers high-volume readings/events and flushes them to the ``PersistenceStoring`` actor in
/// batches; on each flush it also snapshots low-volume device state and active alerts from the
/// in-memory store. A periodic flush keeps storage fresh even when ingestion is slow, and a final
/// flush on stop loses nothing. All persistence work happens through the (off-main) ModelActor.
actor PersistenceCoordinator {
    private let persistence: any PersistenceStoring
    private let store: InMemoryTelemetryStore
    private let batchSize: Int
    private var readingBuffer: [TelemetryReading] = []
    private var eventBuffer: [DeviceEvent] = []
    private var flushTask: Task<Void, Never>?

    init(persistence: any PersistenceStoring, store: InMemoryTelemetryStore, batchSize: Int = 256) {
        self.persistence = persistence
        self.store = store
        self.batchSize = batchSize
    }

    /// Buffers one telemetry item; flushes when the buffer is full.
    func enqueue(_ item: DeviceTelemetry) async {
        switch item {
        case .reading(let reading): readingBuffer.append(reading)
        case .event(let event): eventBuffer.append(event)
        case .location: break // last-known location is captured in the device snapshot on flush
        }
        if readingBuffer.count + eventBuffer.count >= batchSize { await flush() }
    }

    /// Writes buffered readings/events and snapshots devices + active alerts.
    func flush() async {
        let readings = readingBuffer; readingBuffer.removeAll(keepingCapacity: true)
        let events = eventBuffer; eventBuffer.removeAll(keepingCapacity: true)
        if !readings.isEmpty { try? await persistence.appendReadings(readings) }
        if !events.isEmpty { try? await persistence.appendEvents(events) }
        await snapshotDevicesAndAlerts()
    }

    func startPeriodicFlush(interval: Duration = .seconds(5)) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.flush()
            }
        }
    }

    func stopAndFlush() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    private func snapshotDevicesAndAlerts() async {
        guard let assets = try? await store.allAssets() else { return }
        var devices: [Device] = []
        for asset in assets {
            guard let assetDevices = try? await store.devices(inAsset: asset.id) else { continue }
            devices += assetDevices
            for device in assetDevices {
                let alerts = (try? await store.activeAlerts(forDevice: device.id)) ?? []
                try? await persistence.replaceActiveAlerts(alerts, forDevice: device.id)
            }
        }
        try? await persistence.upsertCatalog(assets: assets, devices: devices)
    }
}
