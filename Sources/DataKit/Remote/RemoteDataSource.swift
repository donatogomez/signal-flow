import Foundation
import DomainKit
import NetworkingKit

/// A remote-backed data layer: exposes the same `DomainKit` ports as `SimulatedDataSource`, but reads
/// from a `NetworkingKit` ``RemoteGateway`` instead of the simulation.
///
/// It is **not** wired into the running app yet — the app still defaults to `SimulatedDataSource`.
/// This type exists so the composition root can switch to a real backend later by changing one line,
/// with features, use cases, and the UI untouched. Insights default to the deterministic provider
/// (the on-device Foundation Models provider can be injected just like elsewhere).
public struct RemoteDataSource: Sendable {
    public let assets: any AssetRepository
    public let devices: any DeviceRepository
    public let telemetry: any TelemetryRepository
    public let alerts: any AlertRepository
    public let events: any EventRepository
    public let insights: any InsightsProviding

    public init(gateway: any RemoteGateway, insights: any InsightsProviding = DeterministicInsightsProvider()) {
        self.assets = RemoteAssetRepository(gateway: gateway)
        self.devices = RemoteDeviceRepository(gateway: gateway)
        self.telemetry = RemoteTelemetryRepository(gateway: gateway)
        self.alerts = RemoteAlertRepository(gateway: gateway)
        self.events = RemoteEventRepository(gateway: gateway)
        self.insights = insights
    }

    /// Convenience: build from a base URL and transport (e.g. `URLSessionHTTPClient`, or a
    /// `StubHTTPClient` for previews/tests).
    public init(
        baseURL: URL,
        transport: any HTTPClient,
        retry: RetryPolicy = .default,
        insights: any InsightsProviding = DeterministicInsightsProvider()
    ) {
        self.init(gateway: SignalFlowRemoteGateway(baseURL: baseURL, transport: transport, retry: retry), insights: insights)
    }
}
