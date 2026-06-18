import Foundation
import Observation
import DomainKit

/// A device option in the Insights picker — a render-ready projection.
public struct InsightDeviceOption: Identifiable, Sendable, Hashable {
    public let id: DeviceID
    public let name: String
    public let assetKind: AssetKind
}

/// State for the Insights screen: a device + metric selection and the generated ``DeviceInsight``.
///
/// Depends only on `DomainKit` ports/use cases. It neither knows nor cares whether the insight came
/// from Apple Foundation Models or the deterministic fallback — that's surfaced via
/// `DeviceInsight.source`, decided behind the `InsightsProviding` port at the composition root.
@MainActor
@Observable
public final class InsightsModel {
    public enum Phase: Sendable, Equatable {
        case idle
        case generating
        case ready
        case insufficientData
        case failed(String)
    }

    public private(set) var devices: [InsightDeviceOption] = []
    public var selectedDeviceID: DeviceID?
    public var metric: MetricKind = .temperature
    public private(set) var phase: Phase = .idle
    public private(set) var insight: DeviceInsight?

    public let metricOptions: [MetricKind] = [.temperature, .humidity, .batteryLevel]

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

    /// Loads the device picker. Selects the first device if none is selected yet.
    public func loadDevices() async {
        do {
            let fleet = try await fetchFleet()
            devices = fleet.flatMap { overview in
                overview.devices.map {
                    InsightDeviceOption(id: $0.device.id, name: $0.device.name, assetKind: overview.asset.kind)
                }
            }
            if selectedDeviceID == nil { selectedDeviceID = devices.first?.id }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Generates an insight for the current selection. On-device generation can take a moment, so the
    /// UI shows `.generating` while it runs.
    public func generateInsight() async {
        guard let deviceID = selectedDeviceID else { return }
        phase = .generating
        insight = nil
        do {
            let fullRange = try TimeRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 4_000_000_000)
            )
            insight = try await generate(deviceID: deviceID, metric: metric, range: fullRange)
            phase = .ready
        } catch DomainError.insufficientData {
            phase = .insufficientData
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
