import Observation
import DomainKit
import DataKit

/// The dependency composition root.
///
/// This is the one and only place that assembles concrete implementations: it owns the `DataKit`
/// `SimulatedDataSource` and exposes it solely as `DomainKit` ports. Features receive those ports and
/// never learn what's behind them — swapping the simulated source for a persisted/live one later is a
/// change *here*, nowhere else.
///
/// `@MainActor` because it drives app lifecycle from the UI; `@Observable` so the app/root view can
/// hold it as `@State`.
@MainActor
@Observable
public final class AppContainer {
    private let source: SimulatedDataSource
    private var didBootstrap = false

    // Domain ports — the entire surface features depend on.
    public var assets: any AssetRepository { source.assets }
    public var devices: any DeviceRepository { source.devices }
    public var telemetry: any TelemetryRepository { source.telemetry }
    public var alerts: any AlertRepository { source.alerts }
    public var events: any EventRepository { source.events }
    public var insights: any InsightsProviding { source.insights }

    public init(source: SimulatedDataSource) {
        self.source = source
    }

    /// The real app configuration: a real-time simulated source playing telemetry at 600× wall speed.
    public static func live() -> AppContainer {
        AppContainer(source: .live(seed: 42, timeScale: 600))
    }

    /// A deterministic configuration for previews and tests.
    public static func preview() -> AppContainer {
        AppContainer(source: .deterministic(seed: 42, maxTicks: 80))
    }

    /// Boots the data layer (once) and starts ingestion. Idempotent and safe to call again after
    /// `stop()`.
    public func start() async {
        if !didBootstrap {
            try? await source.bootstrap()
            didBootstrap = true
        }
        await source.start()
    }

    /// Halts ingestion. `stop()` awaits the ingestion loop to completion, so teardown is clean and
    /// cancellation-safe (see DataKit §16.5).
    public func stop() async {
        await source.stop()
    }
}
