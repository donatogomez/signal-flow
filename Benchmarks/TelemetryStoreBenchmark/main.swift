// Telemetry-history benchmark for `InMemoryTelemetryStore` (finding F-05).
//
// Run with optimizations (the only numbers worth comparing):
//
//     swift run -c release TelemetryStoreBenchmark
//
// The workload is fixed so results can be compared across commits on the same machine. Only the
// public DataKit API is used. Readings are built before timing starts, so the timed loops measure
// the store, not UUID generation.

import Foundation
import Darwin
import Synchronization
import DomainKit
import SimulationKit
import DataKit

// MARK: - Workload

let historySizes = [100, 1_000, 2_000, 5_000, 10_000]
let measuredIngestions = 2_000
let warmUpRuns = 1
let measuredRuns = 7
let retrievalCalls = 50

let origin = Date(timeIntervalSince1970: 1_700_000_000)
let deviceID = DeviceID()
let catalog = [DeviceCatalogEntry(
    descriptor: DeviceDescriptor(id: deviceID, assetID: AssetID(), name: "Bench", assetKind: .refrigeratedTruck),
    rules: []
)]

/// One reading per simulated minute, all on the same device and metric (a single series).
func makeReadings(_ count: Int) -> [TelemetryReading] {
    (0..<count).map { index in
        TelemetryReading(
            deviceID: deviceID,
            metric: .temperature,
            value: try! MeasuredValue(magnitude: Double(index % 40), unit: .celsius),
            recordedAt: origin.addingTimeInterval(Double(index) * 60)
        )
    }
}

// MARK: - Allocation counting (diagnostic)

/// Counts heap allocations on every thread through libmalloc's `malloc_logger` hook — the hook
/// Instruments' allocation tracking uses. Figures include the benchmark's own task machinery, so
/// they are comparable between runs of this benchmark, not absolute.
enum AllocationCounter {
    static let count = Atomic<Int>(0)
    static let bytes = Atomic<Int>(0)

    typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    /// Address of libmalloc's `malloc_logger` function pointer (`RTLD_DEFAULT` lookup), kept as an
    /// integer so it is `Sendable`.
    static let slotAddress = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger").map { UInt(bitPattern: $0) }
    static var slot: UnsafeMutablePointer<Logger?>? { slotAddress.flatMap { UnsafeMutablePointer(bitPattern: $0) } }

    static let logger: Logger = { type, _, size, _, _, _ in
        // MALLOC_LOG_TYPE_ALLOCATE == 2; realloc logs as allocate | deallocate.
        guard type & 2 != 0 else { return }
        AllocationCounter.count.add(1, ordering: .relaxed)
        AllocationCounter.bytes.add(Int(size), ordering: .relaxed)
    }

    static var isAvailable: Bool { slot != nil }

    static func measure(_ body: () async -> Void) async -> (count: Int, bytes: Int) {
        guard let slot else { await body(); return (0, 0) }
        count.store(0, ordering: .relaxed)
        bytes.store(0, ordering: .relaxed)
        slot.pointee = logger
        await body()
        slot.pointee = nil
        return (count.load(ordering: .relaxed), bytes.load(ordering: .relaxed))
    }
}

// MARK: - Measurements

func elapsed(_ body: () async -> Void) async -> Duration {
    let clock = ContinuousClock()
    let start = clock.now
    await body()
    return clock.now - start
}

func median(_ values: [Duration]) -> Duration {
    values.sorted()[values.count / 2]
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
}

func microseconds(_ duration: Duration) -> Double { milliseconds(duration) * 1_000 }

/// A store holding exactly `prefill` readings in one series, with the given retention limit.
func makeStore(limit: Int, prefill: [TelemetryReading]) async -> InMemoryTelemetryStore {
    let store = InMemoryTelemetryStore(historyLimit: limit)
    await store.register(catalog)
    for reading in prefill { await store.ingest(.reading(reading)) }
    return store
}

struct Result {
    var size: Int
    var atCapacity: Duration      // `measuredIngestions` ingestions, each evicting the oldest reading
    var belowCapacity: Duration   // same ingestions, limit raised so nothing is evicted (history grows by `measuredIngestions`)
    var fullHistory: Duration     // one `readings(in:)` call returning the whole series
    var recentWindow: Duration    // one `readings(in:)` call returning the newest 10%
    var allocations: (count: Int, bytes: Int)
}

func run(size: Int) async -> Result {
    let prefill = makeReadings(size)
    let incoming = makeReadings(size + measuredIngestions).suffix(measuredIngestions)
    let fullRange = try! TimeRange(start: origin, end: origin.addingTimeInterval(Double(size + measuredIngestions) * 60))
    let recentStart = origin.addingTimeInterval(Double(measuredIngestions + size - size / 10) * 60)
    let recentRange = try! TimeRange(start: recentStart, end: fullRange.end)

    var atCapacity: [Duration] = []
    var belowCapacity: [Duration] = []
    var fullHistory: [Duration] = []
    var recentWindow: [Duration] = []

    for iteration in 0..<(warmUpRuns + measuredRuns) {
        let trimmed = await makeStore(limit: size, prefill: prefill)
        let ingestTime = await elapsed { for reading in incoming { await trimmed.ingest(.reading(reading)) } }

        let untrimmed = await makeStore(limit: size + measuredIngestions, prefill: prefill)
        let appendTime = await elapsed { for reading in incoming { await untrimmed.ingest(.reading(reading)) } }

        var full = 0, recent = 0
        let fullTime = await elapsed {
            for _ in 0..<retrievalCalls { full += try! await trimmed.readings(forDevice: deviceID, metric: .temperature, in: fullRange).count }
        }
        let recentTime = await elapsed {
            for _ in 0..<retrievalCalls { recent += try! await trimmed.readings(forDevice: deviceID, metric: .temperature, in: recentRange).count }
        }
        precondition(full == retrievalCalls * size && recent == retrievalCalls * (size / 10))

        guard iteration >= warmUpRuns else { continue }
        atCapacity.append(ingestTime)
        belowCapacity.append(appendTime)
        fullHistory.append(fullTime / retrievalCalls)
        recentWindow.append(recentTime / retrievalCalls)
    }

    // Allocations are counted in a separate pass so the hook doesn't distort the timings.
    let store = await makeStore(limit: size, prefill: prefill)
    let allocations = await AllocationCounter.measure {
        for reading in incoming { await store.ingest(.reading(reading)) }
    }
    let history = try! await store.readings(forDevice: deviceID, metric: .temperature, in: fullRange)
    precondition(history.count == size && history.last?.recordedAt == incoming.last?.recordedAt)

    return Result(
        size: size, atCapacity: median(atCapacity), belowCapacity: median(belowCapacity),
        fullHistory: median(fullHistory), recentWindow: median(recentWindow), allocations: allocations
    )
}

// MARK: - Report

func format(_ value: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }

#if DEBUG
print("⚠️  Debug build: numbers are diagnostic only. Use `swift run -c release TelemetryStoreBenchmark`.\n")
#endif
print("""
\(measuredIngestions) ingestions per run into one series; median of \(measuredRuns) runs after \(warmUpRuns) warm-up.
Retrieval: median per call over \(retrievalCalls) calls.

| History | Ingest total at capacity (ms) | Per ingestion (µs) | Append, no eviction (µs) | Allocs / ingestion | KB allocated / ingestion | Full history read (µs) | Newest 10% read (µs) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
""")
for size in historySizes {
    let result = await run(size: size)
    let perIngest = microseconds(result.atCapacity) / Double(measuredIngestions)
    let perAppend = microseconds(result.belowCapacity) / Double(measuredIngestions)
    let allocs = AllocationCounter.isAvailable ? format(Double(result.allocations.count) / Double(measuredIngestions), 1) : "n/a"
    let kilobytes = AllocationCounter.isAvailable ? format(Double(result.allocations.bytes) / Double(measuredIngestions) / 1_024, 1) : "n/a"
    print("| \(size) | \(format(milliseconds(result.atCapacity))) | \(format(perIngest)) | \(format(perAppend)) | \(allocs) | \(kilobytes) | \(format(microseconds(result.fullHistory), 1)) | \(format(microseconds(result.recentWindow), 1)) |")
}
