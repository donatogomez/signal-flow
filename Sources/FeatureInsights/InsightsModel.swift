import Foundation
import Observation
import DomainKit

/// Metrics tried per device, in priority order — the first with enough data yields that device's
/// observation. File-private (not a `@MainActor` static) so the off-actor generation tasks can read it.
private let insightFeedMetrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]

/// One observation in the Insights feed — a presentation-layer projection of a ``DeviceInsight`` paired
/// with the device + metric it concerns (the insight carries the words; the subject is known at the call
/// site). This is the seam that keeps the future IntelligenceKit redesign cheap: only this adapter and the
/// model touch `DeviceInsight`; swapping the provider behind `InsightsProviding` won't change the UI.
public struct InsightFeedItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let deviceName: String
    public let metric: MetricKind
    public let observation: String
    public let anomaly: String
    public let recommendation: String
    public let severity: InsightSeverity
    public let confidence: Double
    public let source: InsightSource

    init(insight: DeviceInsight, deviceID: DeviceID, deviceName: String, metric: MetricKind) {
        self.id = "\(deviceID) \(metric.displayName)"
        self.deviceName = deviceName
        self.metric = metric
        self.observation = insight.summary
        self.anomaly = insight.anomalyExplanation
        self.recommendation = insight.recommendation
        self.severity = insight.severity
        self.confidence = insight.confidence
        self.source = insight.source
    }
}

/// State for the Insights screen: a fleet-wide **feed** of observations.
///
/// The feed is assembled by running the **existing** ``GenerateDeviceInsightUseCase`` (behind the
/// `InsightsProviding` port) once per device and adapting each `DeviceInsight` into an
/// ``InsightFeedItem``. This model is pure presentation orchestration — it adds no domain logic and no new
/// port. A later phase can replace the provider (or give it a fleet-native call) behind the same interface
/// without touching this screen.
@MainActor
@Observable
public final class InsightsModel {
    public enum Phase: Sendable, Equatable {
        case loading
        case ready
        case empty
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var items: [InsightFeedItem] = []

    private let fetchFleet: FetchFleetOverviewUseCase
    private let generate: GenerateDeviceInsightUseCase

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        events: any EventRepository,
        insights: any InsightsProviding
    ) {
        self.fetchFleet = FetchFleetOverviewUseCase(assets: assets, devices: devices, alerts: alerts)
        self.generate = GenerateDeviceInsightUseCase(
            devices: devices, assets: assets, telemetry: telemetry, alerts: alerts, events: events, insights: insights
        )
    }

    /// Builds the feed: one observation per device that has enough data, sorted attention-first. Devices
    /// without enough data simply don't contribute an item (no error). Keeps the current feed on refresh.
    public func load() async {
        if items.isEmpty { phase = .loading }
        do {
            let fleet = try await fetchFleet()
            let subjects = fleet.flatMap { overview in
                overview.devices.map { (id: $0.device.id, name: $0.device.name) }
            }
            let range = try TimeRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 4_000_000_000)
            )
            let generate = self.generate
            let collected = await withTaskGroup(of: InsightFeedItem?.self) { group in
                for subject in subjects {
                    group.addTask {
                        await Self.firstObservation(generate: generate, deviceID: subject.id, deviceName: subject.name, range: range)
                    }
                }
                var out: [InsightFeedItem] = []
                for await item in group where item != nil { out.append(item!) }
                return out
            }
            items = collected.sorted(by: Self.attentionOrder)
            phase = items.isEmpty ? .empty : .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// The first metric (in priority order) that has enough data to yield an insight for this device.
    /// Insufficient-data and any per-device failure are swallowed so one device never breaks the feed.
    nonisolated private static func firstObservation(
        generate: GenerateDeviceInsightUseCase,
        deviceID: DeviceID,
        deviceName: String,
        range: TimeRange
    ) async -> InsightFeedItem? {
        for metric in insightFeedMetrics {
            if let insight = try? await generate(deviceID: deviceID, metric: metric, range: range) {
                return InsightFeedItem(insight: insight, deviceID: deviceID, deviceName: deviceName, metric: metric)
            }
        }
        return nil
    }

    /// Most noteworthy first: concern over watch over nominal, then by confidence. Reuses the insight's own
    /// severity + confidence — no new ranking is invented.
    nonisolated private static func attentionOrder(_ a: InsightFeedItem, _ b: InsightFeedItem) -> Bool {
        if a.severity.attentionRank != b.severity.attentionRank {
            return a.severity.attentionRank > b.severity.attentionRank
        }
        return a.confidence > b.confidence
    }
}

private extension InsightSeverity {
    var attentionRank: Int {
        switch self {
        case .concern: 2
        case .watch: 1
        case .nominal: 0
        }
    }
}
