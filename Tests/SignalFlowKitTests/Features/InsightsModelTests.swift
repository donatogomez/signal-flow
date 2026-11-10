import Foundation
import Testing
import DomainKit
@testable import FeatureInsights

@MainActor
@Suite("Insights model")
struct InsightsModelTests {

    /// Builds a model over a single device whose temperature history is `temperatures`.
    private func makeModel(
        temperatures values: [Double],
        insight: DeviceInsight = .sample,
        insights: (any InsightsProviding)? = nil
    ) throws -> InsightsModel {
        let assetID = AssetID()
        let device = try FX.device("Reefer 12", asset: assetID, connectivity: .online)
        let history = try values.enumerated().map {
            try FX.reading(device: device.id, .temperature, $1, unit: .celsius, at: TimeInterval($0 * 60))
        }
        let assets = FakeAssetRepository(
            byID: [assetID: try FX.asset("Reefer 12", .refrigeratedTruck, id: assetID, devices: [device.id])],
            order: [assetID]
        )
        let devices = FakeDeviceRepository(byAsset: [assetID: [device]], byID: [device.id: device])
        let telemetry = FakeTelemetryRepository(history: [device.id: [.temperature: history]])
        return InsightsModel(
            assets: assets, devices: devices, telemetry: telemetry,
            alerts: FakeAlertRepository(), events: FakeEventRepository(),
            insights: insights ?? FakeInsightsProvider(stub: insight)
        )
    }

    @Test("Builds a feed item per device with enough data, adapting the insight")
    func buildsFeed() async throws {
        let model = try makeModel(
            temperatures: [2, 4, 6],
            insight: DeviceInsight(summary: "s", anomalyExplanation: "a", recommendation: "r",
                                   severity: .watch, confidence: 0.7, source: .foundationModel)
        )
        await model.load()

        #expect(model.phase == .ready)
        #expect(model.items.count == 1)
        let item = try #require(model.items.first)
        #expect(item.deviceName == "Reefer 12")
        #expect(item.metric == .temperature)
        #expect(item.recommendation == "r")
        #expect(item.severity == .watch)
        #expect(item.source == .foundationModel)
        // Enriched from the real telemetry trend (rising 2 → 6), not fabricated.
        #expect(item.trend == [2, 4, 6])
        #expect(item.changeText != nil)
        // .watch is actionable, so it surfaces in the recommendations section.
        #expect(model.recommendations.count == 1)
    }

    @Test("A cancelled load isn't presented as an empty feed")
    func cancelledLoadIsNotEmpty() async throws {
        let gate = Latch()
        let model = try makeModel(temperatures: [2, 4, 6], insights: CancellableInsightsProvider(gate: gate))
        let loading = Task { await model.load() }
        loading.cancel()                            // the screen went away mid-load
        await gate.open()
        await loading.value
        #expect(model.phase == .loading)
        #expect(model.items.isEmpty)

        await model.load()                          // the next appearance loads normally
        #expect(model.phase == .ready)
    }

    // MARK: - Progressive first load

    /// A model over one asset whose devices, named `names`, each have a rising temperature history.
    private func makeFleetModel(_ names: [String], insights: any InsightsProviding) throws -> InsightsModel {
        let assetID = AssetID()
        let devices = try names.map { try FX.device($0, asset: assetID, connectivity: .online) }
        var history: [DeviceID: [MetricKind: [TelemetryReading]]] = [:]
        for device in devices {
            history[device.id] = [.temperature: try [2.0, 4, 6].enumerated().map {
                try FX.reading(device: device.id, .temperature, $1, unit: .celsius, at: TimeInterval($0 * 60))
            }]
        }
        return InsightsModel(
            assets: FakeAssetRepository(
                byID: [assetID: try FX.asset("Fleet", .refrigeratedTruck, id: assetID, devices: devices.map(\.id))],
                order: [assetID]
            ),
            devices: FakeDeviceRepository(
                byAsset: [assetID: devices], byID: Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
            ),
            telemetry: FakeTelemetryRepository(history: history),
            alerts: FakeAlertRepository(), events: FakeEventRepository(),
            insights: insights
        )
    }

    /// Waits (up to 2 s) for the load running alongside to reach `condition`.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<2_000 where !condition() { try await Task.sleep(for: .milliseconds(1)) }
    }

    @Test("The first load shows each observation as soon as it's generated, in attention order")
    func firstLoadIsProgressive() async throws {
        let provider = GatedInsightsProvider(severities: ["Reefer A": .concern])
        let model = try makeFleetModel(["Reefer A", "Reefer B"], insights: provider)
        let loading = Task { await model.load() }

        await provider.release("Reefer B")
        try await waitUntil { model.items.count == 1 }
        #expect(model.phase == .ready)                          // shown while A is still generating
        #expect(model.items.map(\.deviceName) == ["Reefer B"])

        await provider.release("Reefer A")
        await loading.value
        #expect(model.items.map(\.deviceName) == ["Reefer A", "Reefer B"]) // the concern goes first
        #expect(model.phase == .ready)
    }

    @Test("Ties keep a fixed order whichever finishes first, and shown cards never swap")
    func orderDoesNotDependOnCompletion() async throws {
        let provider = GatedInsightsProvider()
        let model = try makeFleetModel(["Reefer A", "Reefer B", "Reefer C"], insights: provider)
        let loading = Task { await model.load() }

        await provider.release("Reefer C")
        try await waitUntil { model.items.count == 1 }
        await provider.release("Reefer A")
        try await waitUntil { model.items.count == 2 }
        #expect(model.items.map(\.deviceName) == ["Reefer A", "Reefer C"])
        await provider.release("Reefer B")
        await loading.value
        #expect(model.items.map(\.deviceName) == ["Reefer A", "Reefer B", "Reefer C"])
    }

    @Test("A refresh keeps the current feed until the new one is complete")
    func refreshIsNotProgressive() async throws {
        let provider = GatedInsightsProvider()
        let model = try makeFleetModel(["Reefer A", "Reefer B"], insights: provider)
        await provider.release("Reefer A")
        await provider.release("Reefer B")
        await model.load()
        let first = model.items

        let refreshing = Task { await model.load() }
        await provider.release("Reefer A", call: 1)
        // Give A's new card time to (wrongly) appear. Too short a wait can only let a regression pass,
        // never fail a correct model.
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.items == first)
        await provider.release("Reefer B", call: 1)
        await refreshing.value
        #expect(model.items.map(\.deviceName) == ["Reefer A", "Reefer B"])
    }

    @Test("A first load cancelled after some cards appeared goes back to loading")
    func cancelledProgressiveLoad() async throws {
        let provider = GatedInsightsProvider()
        let model = try makeFleetModel(["Reefer A", "Reefer B"], insights: provider)
        let loading = Task { await model.load() }
        await provider.release("Reefer B")
        try await waitUntil { model.items.count == 1 }

        loading.cancel()                                        // the screen went away mid-load
        await provider.release("Reefer A")
        await loading.value
        #expect(model.phase == .loading)
        #expect(model.items.isEmpty)
    }

    @Test("Empty feed when no device has enough data")
    func emptyFeed() async throws {
        let model = try makeModel(temperatures: [5]) // below the minimum for statistics
        await model.load()
        #expect(model.phase == .empty)
        #expect(model.items.isEmpty)
    }
}

/// Behaves like the on-device provider under cancellation: it waits for `gate`, then throws
/// `CancellationError` if the request was cancelled meanwhile.
private struct CancellableInsightsProvider: InsightsProviding {
    let gate: Latch
    func insight(for context: InsightContext) async throws -> DeviceInsight {
        await gate.wait()
        try Task.checkCancellation()
        return .sample
    }
}

/// Holds each request until the test releases it, so a test decides the order generations finish in.
/// Requests are counted per device: `call: 0` is a device's request in the first load, 1 in the next.
private actor GatedInsightsProvider: InsightsProviding {
    private let severities: [String: InsightSeverity]
    private var latches: [String: [Latch]] = [:]
    private var calls: [String: Int] = [:]

    init(severities: [String: InsightSeverity] = [:]) {
        self.severities = severities
    }

    func release(_ deviceName: String, call: Int = 0) async {
        await latch(deviceName, call).open()
    }

    func insight(for context: InsightContext) async throws -> DeviceInsight {
        let call = calls[context.deviceName, default: 0]
        calls[context.deviceName] = call + 1
        await latch(context.deviceName, call).wait()
        try Task.checkCancellation()
        return DeviceInsight(
            summary: "s", anomalyExplanation: "a", recommendation: "r",
            severity: severities[context.deviceName] ?? .nominal, confidence: 1, source: .foundationModel
        )
    }

    private func latch(_ deviceName: String, _ call: Int) -> Latch {
        var list = latches[deviceName, default: []]
        while list.count <= call { list.append(Latch()) }
        latches[deviceName] = list
        return list[call]
    }
}
