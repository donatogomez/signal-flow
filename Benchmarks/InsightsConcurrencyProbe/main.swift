// Foundation Models concurrency probe for the Insights feed (finding F-18).
//
//     swift run -c release InsightsConcurrencyProbe
//
// Needs a Mac with Apple Intelligence enabled. Generates one insight per simulated device through the
// app's `FoundationModelsInsightProvider`, with at most `limit` generations in flight, and reports
// wall time, per-call latency, and how many calls fell back to the deterministic provider.

import Foundation
import DomainKit
import DataKit
import IntelligenceKit

let limits = [1, 2, 3, 10]
let rounds = 3
let metrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]

guard FoundationModelsInsightProvider.systemModelAvailable else {
    print("The system language model is not available on this Mac.")
    exit(1)
}

let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: 120)
try await source.bootstrap()
await source.ingestAll()
var collectedIDs: [DeviceID] = []
for asset in try await source.assets.allAssets() {
    collectedIDs += try await source.devices.devices(inAsset: asset.id).map(\.id)
}
let deviceIDs = collectedIDs
let generate = GenerateDeviceInsightUseCase(
    devices: source.devices, assets: source.assets, telemetry: source.telemetry,
    alerts: source.alerts, events: source.events,
    insights: FoundationModelsInsightProvider(fallback: DeterministicInsightsProvider())
)
let range = try TimeRange(start: .distantPast, end: .distantFuture)

struct Call: Sendable { var seconds: Double; var source: InsightSource? }

/// The first metric that yields an insight, as the feed does; `source` is nil when none does.
func observe(_ id: DeviceID) async -> Call {
    let start = ContinuousClock.now
    for metric in metrics {
        if let insight = try? await generate(deviceID: id, metric: metric, range: range) {
            let elapsed = ContinuousClock.now - start
            return Call(seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, source: insight.source)
        }
    }
    return Call(seconds: 0, source: nil)
}

func run(limit: Int) async -> (wall: Double, calls: [Call]) {
    let start = ContinuousClock.now
    let calls = await withTaskGroup(of: Call.self) { group in
        var pending = deviceIDs[...]
        for _ in 0..<min(limit, pending.count) { let id = pending.removeFirst(); group.addTask { await observe(id) } }
        var out: [Call] = []
        while let call = await group.next() {
            out.append(call)
            if let id = pending.popFirst() { group.addTask { await observe(id) } }
        }
        return out
    }
    let elapsed = ContinuousClock.now - start
    return (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, calls)
}

func f(_ value: Double) -> String { String(format: "%.2f", value) }

print("\(deviceIDs.count) devices; \(rounds) rounds per limit (first round of each limit shown separately as warm-up).\n")
print("| Limit | Round | Wall (s) | Median call (s) | Slowest call (s) | Model / fallback / none |")
print("| ---: | ---: | ---: | ---: | ---: | --- |")
_ = await run(limit: 1)  // load the model once before measuring
for limit in limits {
    for round in 1...rounds {
        let (wall, calls) = await run(limit: limit)
        let seconds = calls.filter { $0.source != nil }.map(\.seconds).sorted()
        let model = calls.filter { $0.source == .foundationModel }.count
        let fallback = calls.filter { $0.source == .deterministic }.count
        let none = calls.filter { $0.source == nil }.count
        print("| \(limit) | \(round) | \(f(wall)) | \(f(seconds.isEmpty ? 0 : seconds[seconds.count / 2])) | \(f(seconds.last ?? 0)) | \(model) / \(fallback) / \(none) |")
    }
}
