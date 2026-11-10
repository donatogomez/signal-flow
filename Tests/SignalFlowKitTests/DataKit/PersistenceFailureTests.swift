import Foundation
import Testing
import DomainKit
import PersistenceKit
@testable import DataKit

/// How DataKit's persistence mirroring behaves when writes fail (docs/21 §21.4). Failures are injected
/// through ``FaultyPersistence``; overlapping flushes are interleaved with latches, not sleeps.
@Suite("Persistence failures")
struct PersistenceFailureTests {
    private let device = DeviceID()

    private func readings(_ count: Int, from start: Int = 0) throws -> [TelemetryReading] {
        try (start..<(start + count)).map { try DataKitFixtures.reading(deviceID: device, .temperature, 4, at: Double($0) * 60) }
    }

    private func coordinator(
        _ persistence: FaultyPersistence, retryLimit: Int = 16_384, historyTrimInterval: Duration = .seconds(60)
    ) -> PersistenceCoordinator {
        // A batch size no test reaches, so only explicit flushes write.
        PersistenceCoordinator(
            persistence: persistence, store: InMemoryTelemetryStore(), batchSize: 10_000, retryLimit: retryLimit,
            historyTrimInterval: historyTrimInterval
        )
    }

    @Test("A failed write keeps the batch, and the next flush writes it")
    func failedFlushIsRetried() async throws {
        let persistence = FaultyPersistence(failing: true)
        let coordinator = coordinator(persistence)
        let batch = try readings(6)
        let event = DataKitFixtures.event(deviceID: device, .doorOpened, at: 30)
        for reading in batch { await coordinator.enqueue(.reading(reading)) }
        await coordinator.enqueue(.event(event))

        await coordinator.flush()
        #expect(await persistence.storedReadings.isEmpty)
        #expect(await coordinator.unsavedCounts == (6, 1))

        await persistence.setFailing(false)
        let later = try readings(2, from: 6)
        for reading in later { await coordinator.enqueue(.reading(reading)) }
        await coordinator.flush()
        #expect(await persistence.storedReadings == Set((batch + later).map(\.id)))
        #expect(await persistence.storedEvents == [event.id])
        #expect(await coordinator.unsavedCounts == (0, 0))
    }

    @Test("Retrying a partly written batch stores each reading once")
    func partialWriteRetry() async throws {
        let persistence = FaultyPersistence(failing: false, failAfterWriting: 3)
        let coordinator = coordinator(persistence)
        let batch = try readings(8)
        for reading in batch { await coordinator.enqueue(.reading(reading)) }

        await coordinator.flush()                   // writes 3, then fails
        #expect(await persistence.storedReadings.count == 3)
        #expect(await coordinator.unsavedCounts.readings == 8)

        await coordinator.flush()                   // the whole batch again; the store dedupes by id
        #expect(await persistence.storedReadings == Set(batch.map(\.id)))
        #expect(await coordinator.unsavedCounts.readings == 0)
    }

    @Test("The retry buffer is bounded and keeps the newest readings")
    func retryBufferIsBounded() async throws {
        let persistence = FaultyPersistence(failing: true)
        let coordinator = coordinator(persistence, retryLimit: 5)
        let batch = try readings(8)
        for reading in batch { await coordinator.enqueue(.reading(reading)) }

        await coordinator.flush()
        #expect(await coordinator.unsavedCounts.readings == 5)

        await persistence.setFailing(false)
        await coordinator.flush()
        #expect(await persistence.storedReadings == Set(batch.suffix(5).map(\.id)))
    }

    @Test("Overlapping flushes neither lose nor duplicate readings when one of them fails")
    func overlappingFlushes() async throws {
        let entered = Latch()
        let gate = Latch()
        let persistence = FaultyPersistence(failing: false, failFirstCall: true, firstCallEntered: entered, holdFirstCallUntil: gate)
        let coordinator = coordinator(persistence)
        let first = try readings(3)
        let second = try readings(2, from: 3)

        for reading in first { await coordinator.enqueue(.reading(reading)) }
        let held = Task { await coordinator.flush() }  // suspended inside its (failing) write
        await entered.wait()
        for reading in second { await coordinator.enqueue(.reading(reading)) }
        await coordinator.flush()                   // overlaps the held one and succeeds
        #expect(await persistence.storedReadings == Set(second.map(\.id)))

        await gate.open()
        await held.value
        #expect(await coordinator.unsavedCounts.readings == 3)
        await coordinator.flush()
        #expect(await persistence.storedReadings == Set((first + second).map(\.id)))
        #expect(await persistence.successfulWritesPerReading.values.allSatisfy { $0 == 1 })
    }

    @Test("Stopping while writes fail returns, keeping the unsaved items for a later flush")
    func stopDuringFailure() async throws {
        let persistence = FaultyPersistence(failing: true)
        let coordinator = coordinator(persistence)
        let batch = try readings(4)
        await coordinator.startPeriodicFlush(interval: .seconds(3_600))
        for reading in batch { await coordinator.enqueue(.reading(reading)) }

        await coordinator.stopAndFlush()
        #expect(await coordinator.unsavedCounts.readings == 4)

        await persistence.setFailing(false)          // e.g. the next foreground session
        await coordinator.flush()
        #expect(await persistence.storedReadings == Set(batch.map(\.id)))
    }

    // MARK: - Insights

    @Test("A cancelled insight request records nothing")
    func cancelledInsightIsNotRecorded() async throws {
        let persistence = FaultyPersistence(failing: false)
        let store = InMemoryTelemetryStore()
        let provider = PersistingInsightsProvider(base: DeterministicInsightsProvider(), persistence: persistence, store: store)
        let context = try Self.context(device: device)

        let gate = Latch()
        let request = Task {
            await gate.wait()
            return try await provider.insight(for: context)
        }
        request.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await persistence.insightCount == 0)
        #expect(await store.insightHistory(forDevice: device).isEmpty)
    }

    @Test("A failed insight save still returns the insight and keeps it for this session")
    func failedInsightSave() async throws {
        let persistence = FaultyPersistence(failing: true)
        let store = InMemoryTelemetryStore()
        let provider = PersistingInsightsProvider(base: DeterministicInsightsProvider(), persistence: persistence, store: store)

        let insight = try await provider.insight(for: try Self.context(device: device))
        #expect(insight.source == .deterministic)
        #expect(await store.insightHistory(forDevice: device).count == 1)
    }

    static func context(device: DeviceID) throws -> InsightContext {
        InsightContext(
            deviceID: device, deviceName: "Reefer 12", assetKind: .refrigeratedTruck,
            statistics: InsightStatistics(metric: .temperature, unit: .celsius, latest: 4, minimum: 2, maximum: 6,
                                          average: 4, trend: .stable, sampleCount: 12),
            activeAlertCount: 0, recentEventCount: 0,
            range: try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1_000))
        )
    }

    // MARK: - Persistent history (docs/21 §21.9)

    @Test("History is trimmed on the first flush and then once per interval, not on every flush")
    func historyTrimmedOnInterval() async throws {
        let rarely = FaultyPersistence(failing: false)
        let hourly = coordinator(rarely, historyTrimInterval: .seconds(3_600))
        for _ in 0..<4 { await hourly.flush() }
        #expect(await rarely.trimCalls == 1)

        let always = FaultyPersistence(failing: false)
        let everyFlush = coordinator(always, historyTrimInterval: .zero)
        for _ in 0..<4 { await everyFlush.flush() }
        #expect(await always.trimCalls == 4)
    }

    @Test("While a history backlog remains, every flush trims one more step; then the interval applies again")
    func historyBacklogTrimmedEveryFlush() async throws {
        let persistence = FaultyPersistence(failing: false, trimBacklogSteps: 3)
        let coordinator = coordinator(persistence, historyTrimInterval: .seconds(3_600))
        for _ in 0..<6 { await coordinator.flush() }
        // Three trims that leave more behind, the one that finishes, then nothing until the next hour.
        #expect(await persistence.trimCalls == 4)
    }

    @Test("A failed history trim doesn't affect writes, and the next interval tries again")
    func failedTrimKeepsWriting() async throws {
        let persistence = FaultyPersistence(failing: false, failTrims: true)
        let coordinator = coordinator(persistence, historyTrimInterval: .zero)
        let batch = try readings(3)
        for reading in batch { await coordinator.enqueue(.reading(reading)) }
        await coordinator.flush()
        #expect(await persistence.storedReadings == Set(batch.map(\.id)))
        #expect(await coordinator.unsavedCounts == (0, 0))

        await coordinator.flush()
        #expect(await persistence.trimCalls == 2)
    }
}

/// A `PersistenceStoring` that keeps ids only and fails on demand. Like the real store, appends are
/// idempotent by id; `failAfterWriting` stores that many readings of a call before throwing (a partial
/// write), and the first call can be held open to overlap it with another flush.
private actor FaultyPersistence: PersistenceStoring {
    private(set) var storedReadings: Set<ReadingID> = []
    private(set) var storedEvents: Set<EventID> = []
    private(set) var successfulWritesPerReading: [ReadingID: Int] = [:]
    private(set) var insightCount = 0
    private(set) var trimCalls = 0
    private let failTrims: Bool
    private var trimBacklogSteps: Int
    private var failing: Bool
    private var failAfterWriting: Int?
    private var failFirstCall: Bool
    private let firstCallEntered: Latch?
    private let holdFirstCallUntil: Latch?
    private var calls = 0

    init(failing: Bool, failAfterWriting: Int? = nil, failFirstCall: Bool = false, failTrims: Bool = false,
         trimBacklogSteps: Int = 0, firstCallEntered: Latch? = nil, holdFirstCallUntil: Latch? = nil) {
        self.failing = failing
        self.failTrims = failTrims
        self.trimBacklogSteps = trimBacklogSteps
        self.failAfterWriting = failAfterWriting
        self.failFirstCall = failFirstCall
        self.firstCallEntered = firstCallEntered
        self.holdFirstCallUntil = holdFirstCallUntil
    }

    func setFailing(_ failing: Bool) { self.failing = failing }

    func appendReadings(_ readings: [TelemetryReading]) async throws {
        calls += 1
        if calls == 1 {
            await firstCallEntered?.open()
            await holdFirstCallUntil?.wait()
            if failFirstCall { throw CocoaError(.fileWriteUnknown) }
        }
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        if let limit = failAfterWriting {
            failAfterWriting = nil
            for reading in readings.prefix(limit) { storedReadings.insert(reading.id) }
            throw CocoaError(.fileWriteUnknown)
        }
        for reading in readings {
            storedReadings.insert(reading.id)
            successfulWritesPerReading[reading.id, default: 0] += 1
        }
    }

    func appendEvents(_ events: [DeviceEvent]) async throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        for event in events { storedEvents.insert(event.id) }
    }

    func appendInsight(_ insight: InsightRecord) async throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        insightCount += 1
    }

    func loadSnapshot() async throws -> PersistedSnapshot {
        PersistedSnapshot(assets: [], devices: [], latestReadings: [], events: [], alerts: [], insights: [])
    }
    func upsertCatalog(assets: [Asset], devices: [Device]) async throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
    }
    func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) async throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
    }
    /// Reports a backlog on the first `trimBacklogSteps` calls.
    func trimHistory() async throws -> Bool {
        trimCalls += 1
        if failTrims { throw CocoaError(.fileWriteUnknown) }
        guard trimBacklogSteps > 0 else { return false }
        trimBacklogSteps -= 1
        return true
    }
}
