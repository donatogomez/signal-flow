import Foundation
import DomainKit
import SimulationKit
import PersistenceKit

/// Mirrors the live telemetry stream into durable storage, off the hot path.
///
/// It buffers high-volume readings/events and flushes them to the ``PersistenceStoring`` actor in
/// batches; on each flush it also snapshots low-volume device state and active alerts from the
/// in-memory store. A periodic flush keeps storage fresh even when ingestion is slow, and a final
/// flush runs on stop. All persistence work happens through the (off-main) ModelActor.
///
/// **Failed writes** (docs/21 §21.4). Readings and events whose append fails are kept in memory and
/// sent again by the next flush. That is safe because appends are idempotent by id: retrying a batch
/// that was fully or partly written stores each item once. What's kept is bounded by `retryLimit`
/// per kind (the newest items win) and lives only in memory, so a write failure that outlasts the
/// process still loses data. Device/alert snapshot writes aren't kept: every flush rewrites them.
/// Failures are logged once when they start and once when writes recover, not once per flush.
///
/// **Persistent history** (docs/21 §21.9). SwiftData records every save in its persistent history and
/// never deletes it, so a flush also trims it, at most once per `historyTrimInterval`, or on every flush
/// while a backlog from before trimming existed is deleted in bounded steps.
actor PersistenceCoordinator {
    private let persistence: any PersistenceStoring
    private let store: InMemoryTelemetryStore
    private let batchSize: Int
    private let retryLimit: Int
    private var readingBuffer: [TelemetryReading] = []
    private var eventBuffer: [DeviceEvent] = []
    /// Items whose write failed, sent again by the next flush.
    private var unsavedReadings: [TelemetryReading] = []
    private var unsavedEvents: [DeviceEvent] = []
    private var isFailing = false
    private var droppedWhileFailing = 0
    private var flushTask: Task<Void, Never>?
    private let historyTrimInterval: Duration
    private var lastHistoryTrim: ContinuousClock.Instant?
    /// The last trim left older history to delete, so the next flush trims again without waiting.
    private var historyBacklog = false

    init(
        persistence: any PersistenceStoring, store: InMemoryTelemetryStore, batchSize: Int = 256,
        retryLimit: Int = 16_384, historyTrimInterval: Duration = .seconds(60)
    ) {
        self.persistence = persistence
        self.store = store
        self.batchSize = batchSize
        self.retryLimit = retryLimit
        self.historyTrimInterval = historyTrimInterval
    }

    /// Readings and events waiting to be written again after a failure (diagnostics / tests).
    var unsavedCounts: (readings: Int, events: Int) { (unsavedReadings.count, unsavedEvents.count) }

    /// Buffers one telemetry item; flushes when the buffer is full. Only new items count towards a
    /// batch, so a persistent failure doesn't make flushes more frequent.
    func enqueue(_ item: DeviceTelemetry) async {
        switch item {
        case .reading(let reading): readingBuffer.append(reading)
        case .event(let event): eventBuffer.append(event)
        case .location: break // last-known location is captured in the device snapshot on flush
        }
        if readingBuffer.count + eventBuffer.count >= batchSize { await flush() }
    }

    /// Writes buffered (and previously failed) readings/events, then snapshots devices + active alerts.
    ///
    /// Each item is either buffered or in exactly one flush's batch, and the batch is taken before the
    /// first suspension, so overlapping flushes (an actor is reentrant) never write the same item twice
    /// or lose one on success.
    func flush() async {
        let readings = unsavedReadings + readingBuffer
        let events = unsavedEvents + eventBuffer
        unsavedReadings = []
        unsavedEvents = []
        readingBuffer.removeAll(keepingCapacity: true)
        eventBuffer.removeAll(keepingCapacity: true)

        var failure: (any Error)?
        if !readings.isEmpty {
            do { try await persistence.appendReadings(readings) } catch {
                failure = error
                unsavedReadings = retain(readings, alongside: unsavedReadings, by: \.recordedAt)
            }
        }
        if !events.isEmpty {
            do { try await persistence.appendEvents(events) } catch {
                failure = failure ?? error
                unsavedEvents = retain(events, alongside: unsavedEvents, by: \.occurredAt)
            }
        }
        if let error = await snapshotDevicesAndAlerts() { failure = failure ?? error }
        report(failure)
        await trimHistoryIfDue()
    }

    /// Trims persistent history on the first flush and then at most once per `historyTrimInterval`,
    /// except while a backlog remains: then every flush deletes one more bounded step. The time is taken
    /// before the call, so overlapping flushes don't trim twice. A failed trim doesn't affect writes;
    /// the next interval tries again.
    private func trimHistoryIfDue() async {
        let now = ContinuousClock.now
        if !historyBacklog, let lastHistoryTrim, now - lastHistoryTrim < historyTrimInterval { return }
        lastHistoryTrim = now
        do {
            historyBacklog = try await persistence.trimHistory()
        } catch {
            historyBacklog = false
            Log.persistence.error("Trimming persistent history failed; trying again later: \(String(describing: error), privacy: .private)")
        }
    }

    func startPeriodicFlush(interval: Duration = .seconds(5)) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval) // cancellation ends the loop below
                if Task.isCancelled { break }
                await self?.flush()
            }
        }
    }

    /// Stops the periodic flush, waits for any in-flight periodic flush to finish (so it can't write an
    /// older device/alert snapshot after the final one), then performs the final flush. If that flush
    /// fails, the unsaved items stay in memory for the next session's flushes; they are lost if the
    /// process ends first.
    func stopAndFlush() async {
        let periodic = flushTask
        flushTask = nil
        periodic?.cancel()
        await periodic?.value
        await flush()
        if !unsavedReadings.isEmpty || !unsavedEvents.isEmpty {
            Log.persistence.error("Final flush left \(self.unsavedReadings.count) readings and \(self.unsavedEvents.count) events unsaved; \(self.droppedWhileFailing) were dropped")
        }
    }

    /// A failed batch plus whatever an overlapping flush kept meanwhile, capped at `retryLimit` by
    /// keeping the newest items.
    private func retain<Item>(_ failed: [Item], alongside kept: [Item], by timestamp: KeyPath<Item, Date>) -> [Item] {
        var all = failed + kept
        guard all.count > retryLimit else { return all }
        all.sort { $0[keyPath: timestamp] < $1[keyPath: timestamp] }
        let dropped = all.count - retryLimit
        if droppedWhileFailing == 0 {
            Log.persistence.warning("Retry buffer full; dropping the oldest unsaved items")
        }
        droppedWhileFailing += dropped
        return Array(all.suffix(retryLimit))
    }

    /// Logs the transitions between healthy and failing writes, not every failed flush.
    private func report(_ failure: (any Error)?) {
        if let failure {
            guard !isFailing else { return }
            isFailing = true
            Log.persistence.error("Persistence write failed; unsaved items will be retried: \(String(describing: failure), privacy: .private)")
        } else if isFailing {
            isFailing = false
            Log.persistence.notice("Persistence writes recovered; \(self.droppedWhileFailing) unsaved items were dropped")
            droppedWhileFailing = 0
        }
    }

    /// Rewrites the device catalog and active alerts. Returns the first write error, if any. Reads from
    /// the in-memory store are skipped on error, as before: they throw only for ids the store doesn't
    /// know (these come from the store itself) or for values it validated when they were ingested.
    private func snapshotDevicesAndAlerts() async -> (any Error)? {
        guard let assets = try? await store.allAssets() else { return nil }
        var failure: (any Error)?
        var devices: [Device] = []
        for asset in assets {
            guard let assetDevices = try? await store.devices(inAsset: asset.id) else { continue }
            devices += assetDevices
            for device in assetDevices {
                let alerts = (try? await store.activeAlerts(forDevice: device.id)) ?? []
                do { try await persistence.replaceActiveAlerts(alerts, forDevice: device.id) } catch { failure = failure ?? error }
            }
        }
        do { try await persistence.upsertCatalog(assets: assets, devices: devices) } catch { failure = failure ?? error }
        return failure
    }
}
