import Foundation
import Testing
import DomainKit
@testable import PersistenceKit

/// Trimming SwiftData's persistent history (docs/21 §21.9). These run against real on-disk stores,
/// like the app's App Group store, because history is a property of the store file.
@Suite("Persistent history trimming")
struct PersistentHistoryTests {
    private let device = DeviceID()

    /// A new on-disk store in its own directory, removed by `remove(_:)`.
    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "test.store")
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// A store on `url`; a second call on the same `url` is another container on the same file, as the
    /// widget and App Intents open it next to the app.
    private func open(_ url: URL) throws -> PersistenceStore {
        PersistenceStore(modelContainer: try PersistenceController.makeContainer(url: url))
    }

    /// Ten readings of temperature and humidity for round `round`, newer than every earlier round.
    private func batch(_ round: Int) throws -> [TelemetryReading] {
        try (0..<5).flatMap { i -> [TelemetryReading] in
            let at = Double(round * 100 + i)
            return [
                try PX.reading(device: device, .temperature, Double(round), at: at),
                try PX.reading(device: device, .humidity, Double(round), unit: .percent, at: at),
            ]
        }
    }

    @Test("Trimming an empty store deletes nothing and doesn't throw")
    func emptyStore() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        for _ in 0..<3 { try await store.trimHistory() }
        #expect(try await store.historyTransactionCount() == 0)
        #expect(try await store.readingCount() == 0)
    }

    @Test("The first trim keeps everything; the next deletes what came before the first")
    func trimDeletesBeforePreviousCutoff() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        for round in 0..<3 { try await store.appendReadings(try batch(round)) }
        let beforeFirstTrim = try await store.historyTransactionCount()
        try await store.trimHistory()
        #expect(try await store.historyTransactionCount() == beforeFirstTrim) // nothing eligible yet

        for round in 3..<6 { try await store.appendReadings(try batch(round)) }
        let beforeSecondTrim = try await store.historyTransactionCount()
        try await store.trimHistory()
        // Everything older than the newest transaction the first trim saw is gone; that transaction
        // and everything written since are kept.
        #expect(try await store.historyTransactionCount() == beforeSecondTrim - (beforeFirstTrim - 1))
    }

    @Test("Trimming deletes only history: every record and the restored snapshot are unchanged")
    func recordsSurvive() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        let assetID = AssetID()
        try await store.upsertCatalog(
            assets: [try PX.asset(id: assetID, devices: [device])], devices: [try PX.device(id: device, asset: assetID)]
        )
        for round in 0..<4 { try await store.appendReadings(try batch(round)) }
        try await store.appendEvents([PX.event(device: device, at: 30), PX.event(device: device, .doorClosed, at: 40)])
        try await store.replaceActiveAlerts([try PX.alert(device: device)], forDevice: device)
        try await store.appendInsight(PX.insightRecord(device: device))
        let before = try await store.loadSnapshot()
        let readingsBefore = try await store.readingCount()

        try await store.trimHistory()
        try await store.trimHistory()

        #expect(try await store.readingCount() == readingsBefore)
        #expect(Summary(try await store.loadSnapshot()) == Summary(before))
        // And through a container opened afterwards, as after a relaunch.
        #expect(Summary(try await open(url).loadSnapshot()) == Summary(before))
    }

    @Test("History left by an earlier launch is removed after a relaunch")
    func relaunchRemovesEarlierHistory() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let earlier = try open(url)
        for round in 0..<10 { try await earlier.appendReadings(try batch(round)) }
        let readings = try await earlier.readingCount()
        #expect(try await earlier.historyTransactionCount() >= 10)

        let relaunched = try open(url)
        try await relaunched.trimHistory()
        try await relaunched.trimHistory()
        #expect(try await relaunched.historyTransactionCount() == 1) // only the newest transaction
        #expect(try await relaunched.readingCount() == readings)

        try await relaunched.appendReadings(try batch(10))           // and writes carry on
        #expect(try await relaunched.loadSnapshot().latestReadings.allSatisfy { $0.value.magnitude == 10 })
    }

    @Test("Sessions too short for a second trim keep their history; the next longer session deletes all of it")
    func shortSessionsThenLongerOne() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        var counts: [Int] = []
        for session in 0..<5 {                               // each one: launch, write, first trim, quit
            let store = try open(url)
            for round in 0..<2 { try await store.appendReadings(try batch(session * 2 + round)) }
            try await store.trimHistory()
            counts.append(try await store.historyTransactionCount())
        }
        #expect(counts == counts.sorted() && Set(counts).count == counts.count) // it accumulates

        let longer = try open(url)
        try await longer.trimHistory()
        try await longer.trimHistory()
        #expect(try await longer.historyTransactionCount() == 1)
        #expect(try await longer.readingCount() == 100)
    }

    @Test("A large backlog is deleted in bounded steps, oldest first, and the cutoff moves only once it's gone")
    func backlogDeletedInSteps() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        for round in 0..<10 { try await store.appendReadings(try batch(round)) }
        let backlog = try await store.historyTransactionCount()
        try await store.trimHistory()                        // takes the cutoff: the newest transaction
        await store.setMaxTransactionsPerTrim(3)

        #expect(try await store.trimHistory())               // more remains
        #expect(try await store.historyTransactionCount() == backlog - 3)
        try await store.appendReadings(try batch(10))        // written during the backlog: after the cutoff
        var steps = 1
        while try await store.trimHistory() {
            steps += 1
            if steps > backlog { break }                     // a regression must fail, not hang
        }
        #expect(steps <= (backlog - 1 + 2) / 3)               // ⌈(backlog − 1) / 3⌉ deletions at most
        // The cutoff transaction and the write made during the backlog are kept.
        #expect(try await store.historyTransactionCount() == 2)
        #expect(try await store.readingCount() == 110)

        // The backlog's last step moved the cutoff to that write, so the next trim deletes the one before it.
        #expect(try await store.trimHistory() == false)
        #expect(try await store.historyTransactionCount() == 1)
    }

    @Test("Repeated write-and-trim cycles keep history bounded while retention keeps the records")
    func repeatedCyclesStayBounded() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        await store.setRetention(RetentionPolicy(maxReadingsPerSeries: 15))
        var counts: [Int] = []
        for round in 0..<12 {
            try await store.appendReadings(try batch(round))
            try await store.trimHistory()
            counts.append(try await store.historyTransactionCount())
        }
        // Each cycle keeps the previous cycle's newest transaction plus its own (one save, or two once
        // retention starts pruning at the fourth round), so the count stops growing.
        #expect(Set(counts.suffix(8)).count == 1)
        #expect(counts.max()! <= 3)
        #expect(try await store.readingCount() == 30)
    }

    @Test("A glance reader on another container reads correctly while the app writes and trims")
    func concurrentReaderUnaffected() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let app = try open(url)
        await app.setRetention(RetentionPolicy(maxReadingsPerSeries: 20))
        try await app.appendReadings(try batch(0))
        let glance = try open(url)
        let rounds = 30

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for round in 1...rounds {
                    try await app.appendReadings(try batch(round))
                    try await app.trimHistory()
                }
            }
            group.addTask {
                for _ in 0..<60 {
                    let latest = try await glance.loadSnapshot().latestReadings
                    #expect(latest.count == 2)                           // one per series, never torn
                }
            }
            try await group.waitForAll()
        }

        let latest = try await open(url).loadSnapshot().latestReadings
        #expect(latest.count == 2)
        #expect(latest.allSatisfy { $0.value.magnitude == Double(rounds) })
        #expect(try await glance.loadSnapshot().latestReadings.allSatisfy { $0.value.magnitude == Double(rounds) })
    }

    @Test("A failed deletion keeps the cutoff, so the next trim deletes from the same point")
    func failedTrimKeepsCutoff() async throws {
        let url = try makeStoreURL()
        defer { remove(url) }
        let store = try open(url)
        for round in 0..<3 { try await store.appendReadings(try batch(round)) }
        let atFirstTrim = try await store.historyTransactionCount()
        try await store.trimHistory()
        for round in 3..<6 { try await store.appendReadings(try batch(round)) }
        let total = try await store.historyTransactionCount()

        await store.failHistoryTrims(with: CocoaError(.fileWriteUnknown))
        await #expect(throws: CocoaError.self) { try await store.trimHistory() }
        #expect(try await store.historyTransactionCount() == total)

        await store.failHistoryTrims(with: nil)
        try await store.trimHistory()
        #expect(try await store.historyTransactionCount() == total - (atFirstTrim - 1))
        #expect(try await store.readingCount() == 60)
    }
}

/// What a restore shows, compared by identity and value rather than by object.
private struct Summary: Equatable {
    let assets: [String], devices: [String], readings: [String], events: [String], alerts: [String], insights: [String]

    init(_ snapshot: PersistedSnapshot) {
        assets = snapshot.assets.map { "\($0.id)" }.sorted()
        devices = snapshot.devices.map { "\($0.id)" }.sorted()
        readings = snapshot.latestReadings.map { "\($0.id) \($0.value.magnitude)" }.sorted()
        events = snapshot.events.map { "\($0.id)" }.sorted()
        alerts = snapshot.alerts.map { "\($0.id)" }.sorted()
        insights = snapshot.insights.map { "\($0.id)" }.sorted()
    }
}
