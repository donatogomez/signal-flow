import Foundation
import SwiftData
import DomainKit

/// The SwiftData-backed persistence implementation.
///
/// A **`@ModelActor`**: it owns its own `ModelContext` on a dedicated executor, so all reads, writes,
/// saves, and pruning happen **off the main actor**, with serialized, race-free access guaranteed by
/// actor isolation. SwiftData `@Model` objects never leave this actor — every method takes and returns
/// `DomainKit` value types, mapped at the boundary by ``Mapping``.
@ModelActor
public actor PersistenceStore: PersistenceStoring {
    private var retentionPolicy = RetentionPolicy.default
    private var saveFailure: (any Error)?

    /// Overrides the retention caps (used by tests to exercise pruning cheaply).
    public func setRetention(_ policy: RetentionPolicy) { retentionPolicy = policy }

    // MARK: Restore

    public func loadSnapshot() throws -> PersistedSnapshot {
        let assetRecords = try modelContext.fetch(FetchDescriptor<AssetRecord>())
        let deviceRecords = try modelContext.fetch(FetchDescriptor<DeviceRecord>())

        let latestReadings = try latestReadingPerSeries()

        let eventRecords = try modelContext.fetch(FetchDescriptor<EventRecord>())
        let alertRecords = try modelContext.fetch(FetchDescriptor<AlertRecord>())
        let insightRecords = try modelContext.fetch(FetchDescriptor<InsightHistoryRecord>())

        return PersistedSnapshot(
            assets: try assetRecords.map(Mapping.asset),
            devices: try deviceRecords.map(Mapping.device),
            latestReadings: try latestReadings.map(Mapping.reading),
            events: try eventRecords.map(Mapping.event),
            alerts: try alertRecords.map(Mapping.alert),
            insights: try insightRecords.map(Mapping.insight)
        )
    }

    /// The newest reading of every (device, metric) series, **without materializing the history**.
    ///
    /// The readings table holds up to `maxReadingsPerSeries` rows per series (tens of thousands in
    /// total), but restore and the glance surfaces only need one row per series — and the widget
    /// extension runs under a tight memory limit. So this is a skip-scan: each query fetches a single
    /// row from a device or series not seen yet. Cost is one tiny query per series (plus one per
    /// device), and only those rows are ever loaded.
    private func latestReadingPerSeries() throws -> [ReadingRecord] {
        var latest: [ReadingRecord] = []
        var seenDevices: [String] = []
        while let deviceID = try firstReading(where: #Predicate { !seenDevices.contains($0.deviceID) })?.deviceID {
            seenDevices.append(deviceID)
            var seenMetrics: [String] = []
            while let newest = try firstReading(
                where: #Predicate { $0.deviceID == deviceID && !seenMetrics.contains($0.metricKey) },
                newestFirst: true
            ) {
                latest.append(newest)
                seenMetrics.append(newest.metricKey)
            }
        }
        return latest
    }

    private func firstReading(where predicate: Predicate<ReadingRecord>, newestFirst: Bool = false) throws -> ReadingRecord? {
        var descriptor = FetchDescriptor<ReadingRecord>(
            predicate: predicate,
            sortBy: newestFirst ? [SortDescriptor(\.recordedAt, order: .reverse)] : []
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: Catalog

    public func upsertCatalog(assets: [Asset], devices: [Device]) throws {
        for asset in assets {
            let id = asset.id.rawValue.uuidString
            if let existing = try fetchAsset(id: id) {
                let mapped = Mapping.record(asset)
                existing.name = mapped.name
                existing.kindRaw = mapped.kindRaw
                existing.deviceIDs = mapped.deviceIDs
                existing.latitude = mapped.latitude
                existing.longitude = mapped.longitude
                existing.altitude = mapped.altitude
            } else {
                modelContext.insert(Mapping.record(asset))
            }
        }
        for device in devices {
            let id = device.id.rawValue.uuidString
            if let existing = try fetchDevice(id: id) {
                let mapped = Mapping.record(device)
                existing.name = mapped.name
                existing.connectivityRaw = mapped.connectivityRaw
                existing.signalMagnitude = mapped.signalMagnitude
                existing.signalUnitRaw = mapped.signalUnitRaw
                existing.lastSeenAt = mapped.lastSeenAt
                existing.latitude = mapped.latitude
                existing.longitude = mapped.longitude
                existing.altitude = mapped.altitude
            } else {
                modelContext.insert(Mapping.record(device))
            }
        }
        try save()
    }

    // MARK: Telemetry / events / alerts / insights

    public func appendReadings(_ readings: [TelemetryReading]) throws {
        guard !readings.isEmpty else { return }
        var touched: Set<String> = []
        for reading in readings {
            let record = Mapping.record(reading)
            if try fetchReading(id: record.id) == nil { modelContext.insert(record) }
            touched.insert("\(record.deviceID)|\(record.metricKey)")
        }
        try save()
        for key in touched {
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            try pruneReadings(deviceID: String(parts[0]), metricKey: String(parts[1]))
        }
        try save()
    }

    public func appendEvents(_ events: [DeviceEvent]) throws {
        guard !events.isEmpty else { return }
        var touched: Set<String> = []
        for event in events {
            let record = Mapping.record(event)
            if try fetchEvent(id: record.id) == nil { modelContext.insert(record) }
            touched.insert(record.deviceID)
        }
        try save()
        for deviceID in touched { try pruneEvents(deviceID: deviceID) }
        try save()
    }

    public func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) throws {
        let id = deviceID.rawValue.uuidString
        let existing = try modelContext.fetch(
            FetchDescriptor<AlertRecord>(predicate: #Predicate { $0.deviceID == id })
        )
        for record in existing { modelContext.delete(record) }
        for alert in alerts { modelContext.insert(Mapping.record(alert)) }
        try save()
    }

    public func appendInsight(_ insight: InsightRecord) throws {
        let record = Mapping.record(insight)
        if try fetchInsight(id: record.id) == nil { modelContext.insert(record) }
        try save()
        try pruneInsights(deviceID: record.deviceID)
        try save()
    }

    // MARK: Saving

    /// Commits the context's pending changes. If that fails they are discarded, so every write starts
    /// from what was last committed: a caller retries from its own copy, a failure can't pile up
    /// pending changes, and an unrelated later save never commits changes the caller gave up on.
    private func save() throws {
        do {
            if let saveFailure { throw saveFailure }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Makes every save fail with `error` until called with `nil` (tests: SwiftData can't be made to
    /// fail on demand).
    func failSaves(with error: (any Error)?) { saveFailure = error }

    // MARK: Diagnostics (for tests)

    public func readingCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ReadingRecord>())
    }

    // MARK: Retention

    private func pruneReadings(deviceID: String, metricKey: String) throws {
        let cap = retentionPolicy.maxReadingsPerSeries
        var descriptor = FetchDescriptor<ReadingRecord>(
            predicate: #Predicate { $0.deviceID == deviceID && $0.metricKey == metricKey },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchOffset = cap
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
    }

    private func pruneEvents(deviceID: String) throws {
        var descriptor = FetchDescriptor<EventRecord>(
            predicate: #Predicate { $0.deviceID == deviceID },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchOffset = retentionPolicy.maxEventsPerDevice
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
    }

    private func pruneInsights(deviceID: String) throws {
        var descriptor = FetchDescriptor<InsightHistoryRecord>(
            predicate: #Predicate { $0.deviceID == deviceID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = retentionPolicy.maxInsightsPerDevice
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
    }

    // MARK: Fetch-by-id helpers

    private func fetchAsset(id: String) throws -> AssetRecord? {
        var d = FetchDescriptor<AssetRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func fetchDevice(id: String) throws -> DeviceRecord? {
        var d = FetchDescriptor<DeviceRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func fetchReading(id: String) throws -> ReadingRecord? {
        var d = FetchDescriptor<ReadingRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func fetchEvent(id: String) throws -> EventRecord? {
        var d = FetchDescriptor<EventRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func fetchInsight(id: String) throws -> InsightHistoryRecord? {
        var d = FetchDescriptor<InsightHistoryRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
