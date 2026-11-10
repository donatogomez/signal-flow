// History-read benchmark for the two periodic readers of telemetry history (finding F-08):
// the watch snapshot (every 5 s) and the device detail screen (every 3 s).
//
// Run with optimizations (the only numbers worth comparing):
//
//     swift run -c release HistoryReadBenchmark
//
// The workload is fixed so results can be compared across commits on the same machine. Only public
// API is used: the store through the `TelemetryRepository` port, and the detail screen through
// `DeviceDetailModel.refresh()`, which is the work the screen does on the main actor each tick.

import Foundation
import DomainKit
import SimulationKit
import DataKit
import FeatureDeviceDetail

// MARK: - Workload

let seriesSizes = [100, 1_000, 10_000]
let deviceCount = 10
let metrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]
let watchMetrics: [MetricKind] = [.temperature, .humidity]
let watchPointCount = 8
let warmUpRuns = 2
let measuredRuns = 15

let origin = Date(timeIntervalSince1970: 1_700_000_000)
let fullRange = try! TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 4_000_000_000))

/// A store with `deviceCount` devices, each holding `size` readings per metric, one per simulated
/// minute. Magnitudes follow a slow wave plus a spike every 997 readings, so extremes are known.
func makeStore(size: Int) async -> (InMemoryTelemetryStore, [DeviceID]) {
    let store = InMemoryTelemetryStore()
    let ids = (0..<deviceCount).map { _ in DeviceID() }
    await store.register(ids.map {
        DeviceCatalogEntry(descriptor: DeviceDescriptor(id: $0, assetID: AssetID(), name: "Bench", assetKind: .refrigeratedTruck), rules: [])
    })
    for id in ids {
        for metric in metrics {
            for index in 0..<size {
                let wave = 50 + 20 * sin(Double(index) / 150)
                let magnitude = index % 997 == 500 ? 99 : wave
                let reading = TelemetryReading(
                    deviceID: id, metric: metric,
                    value: try! MeasuredValue(magnitude: magnitude, unit: metric.canonicalUnit),
                    recordedAt: origin.addingTimeInterval(Double(index) * 60)
                )
                await store.ingest(.reading(reading))
            }
        }
    }
    return (store, ids)
}

// MARK: - Measurements

func elapsed(isolation: isolated (any Actor)? = #isolation, _ body: () async -> Void) async -> Duration {
    let clock = ContinuousClock()
    let start = clock.now
    await body()
    return clock.now - start
}

func median(_ values: [Duration]) -> Duration { values.sorted()[values.count / 2] }

func microseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12
}

/// What the watch snapshot read before F-08: the whole series through the port, re-sorted, of which the
/// snapshot builder keeps the newest `watchPointCount`.
func watchReadFullSeries(_ telemetry: some TelemetryRepository, _ ids: [DeviceID]) async -> Int {
    var kept = 0
    for id in ids {
        for metric in watchMetrics {
            let readings = try! await telemetry.readings(forDevice: id, metric: metric, in: fullRange)
            kept += readings.sorted { $0.recordedAt < $1.recordedAt }.suffix(watchPointCount).count
        }
    }
    return kept
}

/// What the watch snapshot reads since F-08: only the newest `watchPointCount` readings of each series.
func watchReadRecent(_ telemetry: some TelemetryRepository, _ ids: [DeviceID]) async -> Int {
    var kept = 0
    for id in ids {
        for metric in watchMetrics {
            kept += try! await telemetry.recentReadings(forDevice: id, metric: metric, limit: watchPointCount).count
        }
    }
    return kept
}

struct Result {
    var size: Int
    var watchFull: Duration
    var watchRecent: Duration
    var detailRefresh: Duration
    var chartPoints: Int
}

@MainActor
func run(size: Int) async -> Result {
    let (store, ids) = await makeStore(size: size)
    let telemetry = StoreTelemetryRepository(store: store)
    let model = DeviceDetailModel(
        deviceID: ids[0],
        devices: StoreDeviceRepository(store: store),
        telemetry: telemetry,
        alerts: StoreAlertRepository(store: store),
        events: StoreEventRepository(store: store)
    )

    var watchFull: [Duration] = []
    var watchRecent: [Duration] = []
    var detail: [Duration] = []
    for iteration in 0..<(warmUpRuns + measuredRuns) {
        var kept = 0
        let watchTime = await elapsed { kept = await watchReadFullSeries(telemetry, ids) }
        precondition(kept == ids.count * watchMetrics.count * min(size, watchPointCount))
        let recentTime = await elapsed { kept = await watchReadRecent(telemetry, ids) }
        precondition(kept == ids.count * watchMetrics.count * min(size, watchPointCount))
        let detailTime = await elapsed { await model.refresh() }
        precondition(model.phase == .loaded && model.trends.count == metrics.count)
        guard iteration >= warmUpRuns else { continue }
        watchFull.append(watchTime)
        watchRecent.append(recentTime)
        detail.append(detailTime)
    }
    let points = model.trends.map(\.points.count).reduce(0, +)
    return Result(size: size, watchFull: median(watchFull), watchRecent: median(watchRecent), detailRefresh: median(detail), chartPoints: points)
}

// MARK: - Report

func format(_ value: Double) -> String { String(format: "%.0f", value) }

#if DEBUG
print("⚠️  Debug build: numbers are diagnostic only. Use `swift run -c release HistoryReadBenchmark`.\n")
#endif
print("""
\(deviceCount) devices × \(metrics.count) metrics; median of \(measuredRuns) runs after \(warmUpRuns) warm-up.
Watch read: \(deviceCount) devices × \(watchMetrics.count) metrics, keeping the newest \(watchPointCount) of each.
Detail refresh: one `DeviceDetailModel.refresh()`; chart points summed over its \(metrics.count) series.

| Readings per series | Watch read, whole series (µs) | Watch read, newest only (µs) | Detail refresh (µs) | Chart points |
| ---: | ---: | ---: | ---: | ---: |
""")
for size in seriesSizes {
    let result = await run(size: size)
    print("| \(size) | \(format(microseconds(result.watchFull))) | \(format(microseconds(result.watchRecent))) | \(format(microseconds(result.detailRefresh))) | \(result.chartPoints) |")
}
