// SwiftData write-path benchmark for `PersistenceStore.appendReadings` (findings F-09 and F-15).
//
//     swift run -c release PersistenceWriteBenchmark
//
// The store is on disk in a temporary directory with the app's default retention (2,000 readings per
// device and metric). Readings arrive like the live app's: 10 devices × 3 metrics, one reading per
// series per tick, flushed in batches of 256 (`PersistenceCoordinator`'s batch size). The live app
// produces about 300 readings per second, so a batch arrives roughly every 850 ms; that is the budget a
// flush has before the ingestion stream starts to queue (see docs/07 §7.2).

import Foundation
import Darwin
import DomainKit
import PersistenceKit
import SnapshotKit

let devices = (0..<10).map { _ in DeviceID() }
let metrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]
let batchSize = 256
let seriesCount = devices.count * metrics.count
let steadyRows = seriesCount * RetentionPolicy.default.maxReadingsPerSeries
let origin = Date(timeIntervalSince1970: 1_700_000_000)
/// `--keep` leaves the store on disk for inspection; `--extra N` writes N more readings at steady state.
/// `--trim-every N` trims SwiftData's persistent history every N batches of the extra phase, as the
/// app's persistence coordinator does on its own interval (docs/21 §21.9).
let keepStore = CommandLine.arguments.contains("--keep")
func option(_ name: String) -> Int? {
    CommandLine.arguments.firstIndex(of: name).flatMap { $0 + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[$0 + 1]) : nil }
}
let extraRows = option("--extra") ?? 0
let trimEvery = option("--trim-every")

/// `--trim-store PATH` opens an existing store (one a `--keep` run left) and trims its history as the app
/// does after an update: the first trim takes the cutoff, the next ones delete the backlog in bounded steps.
if let index = CommandLine.arguments.firstIndex(of: "--trim-store"), index + 1 < CommandLine.arguments.count {
    let url = URL(filePath: CommandLine.arguments[index + 1])
    var store: PersistenceStore?
    let open = try await timed { store = PersistenceStore(modelContainer: try PersistenceController.makeContainer(url: url)) }
    let rows = try await store!.readingCount()
    let first = try await timed { try await store!.trimHistory() }
    var steps: [Double] = []
    var more = true
    while more { steps.append(try await timed { more = try await store!.trimHistory() }) }
    let after = try await store!.readingCount()
    print("Opened in \(f(open)) ms; readings \(rows) before, \(after) after. First trim \(f(first)) ms (takes the cutoff).")
    print("Backlog deleted in \(steps.count) steps: \(f(steps.reduce(0, +))) ms in all, median \(f(median(steps))) ms, slowest \(f(steps.max()!)) ms.")
    exit(after == rows ? 0 : 1)
}

/// `--ingest-store PATH` writes into an existing store at the live rate, one batch of 256 every ~853 ms on
/// the store's own series, and trims history like the coordinator: the first flush takes the cutoff, then
/// once per 60 s, and every flush while a backlog remains. A batch's latency runs from the arrival of its
/// last reading to the end of its flush, so time spent queued behind a slow flush counts. It stops 70
/// batches after the backlog is gone.
if let index = CommandLine.arguments.firstIndex(of: "--ingest-store"), index + 1 < CommandLine.arguments.count {
    let store = PersistenceStore(modelContainer: try PersistenceController.makeContainer(url: URL(filePath: CommandLine.arguments[index + 1])))
    let series = try await store.loadSnapshot().latestReadings
    let newest = series.map(\.recordedAt).max()!
    let perBatch = Duration.seconds(Double(batchSize) / 300)
    let start = ContinuousClock.now
    var lastTrim: ContinuousClock.Instant?
    var backlog = false, backlogSeen = false
    var latencies: [Double] = [], flushes: [Double] = [], steps: [Double] = [], queued: [Int] = []
    var written = 0, batchesAfterBacklog = 0
    while batchesAfterBacklog < 70 && written < 2_000 * batchSize {   // ~28 min at most
        let arrived = start + perBatch * (written / batchSize + 1)   // this batch's last reading
        if ContinuousClock.now < arrived { try await Task.sleep(until: arrived) }
        let begin = ContinuousClock.now
        queued.append(Int((begin - start) / perBatch) * batchSize - written)
        let batch = (written..<(written + batchSize)).map { i in
            let s = series[i % series.count]
            return TelemetryReading(deviceID: s.deviceID, metric: s.metric, value: s.value,
                                    recordedAt: newest.addingTimeInterval(Double(i / series.count + 1) * 6))
        }
        try await store.appendReadings(batch)
        if backlog || lastTrim.map({ begin - $0 >= .seconds(60) }) ?? true {
            lastTrim = begin
            let wasBacklog = backlog
            let step = try await timed { backlog = try await store.trimHistory() }
            if backlog || wasBacklog { steps.append(step) }
            backlogSeen = backlogSeen || backlog
        }
        written += batchSize
        let end = ContinuousClock.now
        flushes.append(milliseconds(end - begin))
        latencies.append(milliseconds(end - arrived))
        if backlogSeen && !backlog { batchesAfterBacklog += 1 }
    }
    func pct(_ v: [Double], _ p: Double) -> Double { v.sorted()[min(v.count - 1, Int(Double(v.count) * p))] }
    let elapsed = milliseconds(ContinuousClock.now - start) / 1000
    print("Ingested \(written) readings over \(series.count) series in \(f(elapsed)) s: \(f(Double(written) / elapsed, 0)) readings/s (produced: 300/s).")
    print("Flush (write + trim): p50 \(f(pct(flushes, 0.5))) ms, p95 \(f(pct(flushes, 0.95))) ms, max \(f(flushes.max()!)) ms.")
    print("Latency from arrival: p50 \(f(pct(latencies, 0.5))) ms, p95 \(f(pct(latencies, 0.95))) ms, max \(f(latencies.max()!)) ms.")
    print("Queued readings at flush start (this batch included): max \(queued.max()!), last \(queued.last!).")
    print("Backlog steps: \(steps.count), p50 \(f(pct(steps, 0.5))) ms, p95 \(f(pct(steps, 0.95))) ms, max \(f(steps.max() ?? 0)) ms.")
    print("Step times (ms): " + steps.map { f($0) }.joined(separator: ","))
    exit(0)
}

let directory = FileManager.default.temporaryDirectory.appending(path: "persistence-bench-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let storeURL = directory.appending(path: "bench.store")
defer { if !keepStore { try? FileManager.default.removeItem(at: directory) } }

/// The `index`-th reading of the live interleaving: series round-robin, one tick (6 s) per round.
func reading(_ index: Int, onlySeries: Int? = nil) -> TelemetryReading {
    let series = onlySeries ?? index % seriesCount
    let tick = onlySeries == nil ? index / seriesCount : index
    return TelemetryReading(
        deviceID: devices[series / metrics.count], metric: metrics[series % metrics.count],
        value: try! MeasuredValue(magnitude: Double(index % 40), unit: metrics[series % metrics.count].canonicalUnit),
        recordedAt: origin.addingTimeInterval(Double(tick) * 6)
    )
}

func milliseconds(_ d: Duration) -> Double { Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15 }
func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
func f(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

func storeSizeMB() -> Double {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    return Double(bytes) / 1_048_576
}

/// One file of the store (`""` for the database itself, `"-wal"` for its write-ahead log).
func fileSizeMB(_ suffix: String) -> Double {
    let url = directory.appending(path: "bench.store\(suffix)")
    return Double((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_048_576
}

func timed(_ body: () async throws -> Void) async rethrows -> Double {
    let start = ContinuousClock.now
    try await body()
    return milliseconds(ContinuousClock.now - start)
}

#if DEBUG
print("⚠️  Debug build: numbers are diagnostic only. Use `swift run -c release PersistenceWriteBenchmark`.\n")
#endif

let store = PersistenceStore(modelContainer: try PersistenceController.makeContainer(url: storeURL))
let footprintStart = footprintMB()
var next = 0

// 1. Fill from empty to past the retention steady state, timing every batch.
print("Fill: \(seriesCount) series, batches of \(batchSize), retention \(RetentionPolicy.default.maxReadingsPerSeries) per series (steady state \(steadyRows) rows).\n")
print("| Rows before batch | Median batch (ms) | Slowest batch (ms) | Store on disk (MB) | Footprint (MB) |")
print("| ---: | ---: | ---: | ---: | ---: |")
let checkpoints = [0, 15_000, 30_000, 45_000, 60_000, 90_000, 120_000]
var window: [Double] = []
var windowStart = 0
let totalToWrite = 120_000 + 20 * batchSize
while next < totalToWrite {
    let batch = (next..<(next + batchSize)).map { reading($0) }
    window.append(try await timed { try await store.appendReadings(batch) })
    next += batchSize
    if let checkpoint = checkpoints.last(where: { $0 <= windowStart }), window.count == 20 {
        let rows = try await store.readingCount()
        print("| \(checkpoint == windowStart ? "\(windowStart)" : "\(windowStart)") (now \(rows)) | \(f(median(window))) | \(f(window.max()!)) | \(f(storeSizeMB(), 2)) | \(f(footprintMB())) |")
    }
    if window.count == 20 || next >= totalToWrite {
        window = []
        windowStart = checkpoints.first(where: { $0 >= next }) ?? next
        // Skip ahead without timing until the next checkpoint.
        while next < windowStart {
            let skip = (next..<(next + batchSize)).map { reading($0) }
            try await store.appendReadings(skip)
            next += batchSize
        }
    }
}

// 2. At steady state: a new batch, the same batch sent again (a retry after a commit), and a new
//    batch on a single series (one prune instead of up to 30).
let runs = 21
var fresh: [Double] = [], retry: [Double] = [], single: [Double] = []
var singleNext = next
for _ in 0..<runs {
    let batch = (next..<(next + batchSize)).map { reading($0) }
    fresh.append(try await timed { try await store.appendReadings(batch) })
    retry.append(try await timed { try await store.appendReadings(batch) })
    next += batchSize
    let one = (singleNext..<(singleNext + batchSize)).map { reading($0 + 10_000_000, onlySeries: 0) }
    single.append(try await timed { try await store.appendReadings(one) })
    singleNext += batchSize
}
// 3. A longer run at steady state, optionally trimming history on an interval.
var extraWritten = 0
var batchesSinceTrim = 0
var trims: [Double] = []
var historyBacklog = false   // like the coordinator, trim again on the next batch while a backlog remains
var extraBatches: [Double] = []
if extraRows > 0 {
    print("\nExtra phase: \(extraRows) readings, history trimmed \(trimEvery.map { "every \($0) batches" } ?? "never").\n")
    print("| Extra readings | Database (MB) | WAL (MB) | Footprint (MB) |")
    print("| ---: | ---: | ---: | ---: |")
}
while extraWritten < extraRows {
    let batch = (next..<(next + batchSize)).map { reading($0) }
    extraBatches.append(try await timed { try await store.appendReadings(batch) })
    next += batchSize
    extraWritten += batchSize
    batchesSinceTrim += 1
    if let trimEvery, batchesSinceTrim >= trimEvery || historyBacklog {
        trims.append(try await timed { historyBacklog = try await store.trimHistory() })
        batchesSinceTrim = 0
    }
    if extraWritten % 51_200 == 0 {
        print("| \(extraWritten) | \(f(fileSizeMB(""), 2)) | \(f(fileSizeMB("-wal"), 2)) | \(f(footprintMB())) |")
    }
}
let rows = try await store.readingCount()
precondition(rows == steadyRows, "retention should hold the store at \(steadyRows) rows, found \(rows)")

print("""

Steady state (\(rows) rows), median of \(runs):

| Batch of \(batchSize) | Median (ms) | Per reading (µs) | Readings/s |
| --- | ---: | ---: | ---: |
| New readings over \(seriesCount) series (the live case) | \(f(median(fresh))) | \(f(median(fresh) * 1000 / Double(batchSize), 0)) | \(f(Double(batchSize) / median(fresh) * 1000, 0)) |
| Same batch again (retry: every id found, nothing inserted) | \(f(median(retry))) | \(f(median(retry) * 1000 / Double(batchSize), 0)) | — |
| New readings on one series (one prune) | \(f(median(single))) | \(f(median(single) * 1000 / Double(batchSize), 0)) | \(f(Double(batchSize) / median(single) * 1000, 0)) |

Store on disk: \(f(storeSizeMB(), 2)) MB. Footprint: \(f(footprintStart)) MB at start, \(f(footprintMB())) MB now.
Live budget: one batch per ~850 ms at 300 readings/s.
""")
if !extraBatches.isEmpty {
    print("Extra phase: median batch \(f(median(extraBatches))) ms, slowest \(f(extraBatches.max()!)) ms.")
}
if !trims.isEmpty {
    print("History trims: \(trims.count), median \(f(median(trims))) ms, slowest \(f(trims.max()!)) ms.")
}

// 4. What a relaunch and a glance surface pay: open a new container on the same file, then read the
//    widget snapshot through it, as `WidgetSnapshotReader.shared()` does in the widget and App Intents.
var opens: [Double] = [], reads: [Double] = []
for _ in 0..<7 {
    var reopened: PersistenceStore?
    opens.append(try await timed { reopened = PersistenceStore(modelContainer: try PersistenceController.makeContainer(url: storeURL)) })
    let reader = WidgetSnapshotReader(store: reopened!)
    reads.append(try await timed { _ = try await reader.read() })
}
print("Reopen (new container on the same file): median \(f(median(opens))) ms. Widget snapshot read: median \(f(median(reads))) ms (7 runs).")
if keepStore { print("Store kept at \(storeURL.path)") }
