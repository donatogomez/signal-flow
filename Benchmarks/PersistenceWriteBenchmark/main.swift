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

let devices = (0..<10).map { _ in DeviceID() }
let metrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]
let batchSize = 256
let seriesCount = devices.count * metrics.count
let steadyRows = seriesCount * RetentionPolicy.default.maxReadingsPerSeries
let origin = Date(timeIntervalSince1970: 1_700_000_000)
/// `--keep` leaves the store on disk for inspection; `--extra N` writes N more readings at steady state.
let keepStore = CommandLine.arguments.contains("--keep")
let extraRows = CommandLine.arguments.firstIndex(of: "--extra").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? 0
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
var extraWritten = 0
while extraWritten < extraRows {
    let batch = (next..<(next + batchSize)).map { reading($0) }
    try await store.appendReadings(batch)
    next += batchSize
    extraWritten += batchSize
    if extraWritten % 51_200 == 0 { print("after \(extraWritten) more readings: \(f(storeSizeMB(), 2)) MB on disk") }
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
if keepStore { print("Store kept at \(storeURL.path)") }
