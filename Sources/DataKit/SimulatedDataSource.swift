import DomainKit
import SimulationKit

/// The DataKit composition root for a simulation-backed data layer.
///
/// It assembles the store, the simulated fleet, the ingestion adapter, and the `DomainKit`-typed
/// repositories, and exposes only domain ports plus lifecycle controls. Construct it through the
/// `deterministic` / `live` factories so callers never name a SimulationKit type — the bridge is
/// fully encapsulated.
public struct SimulatedDataSource: Sendable {

    /// Domain ports — the only thing features (via the composition root) ever consume.
    public let assets: any AssetRepository
    public let devices: any DeviceRepository
    public let telemetry: any TelemetryRepository
    public let alerts: any AlertRepository
    public let events: any EventRepository
    public let insights: any InsightsProviding

    private let store: InMemoryTelemetryStore
    private let engine: SimulationEngineActor
    private let adapter: SimulationTelemetryAdapter

    init(seed: UInt64, clock: any SimulationClock, maxTicks: Int?, insights: any InsightsProviding) {
        let store = InMemoryTelemetryStore()
        let engine = SimulationFleet.standard(seed: seed, clock: clock, maxTicks: maxTicks)
        self.store = store
        self.engine = engine
        self.adapter = SimulationTelemetryAdapter(engine: engine, store: store)
        self.assets = StoreAssetRepository(store: store)
        self.devices = StoreDeviceRepository(store: store)
        self.telemetry = StoreTelemetryRepository(store: store)
        self.alerts = StoreAlertRepository(store: store)
        self.events = StoreEventRepository(store: store)
        self.insights = insights
    }

    /// A reproducible source that produces `maxTicks` of telemetry as fast as possible — for tests and
    /// previews. Pair with `bootstrap()` + `ingestAll()`.
    ///
    /// The insight provider is injectable so the composition root can supply a Foundation Models
    /// provider; it defaults to the deterministic one.
    public static func deterministic(
        seed: UInt64 = 42,
        maxTicks: Int = 120,
        insights: any InsightsProviding = DeterministicInsightsProvider()
    ) -> SimulatedDataSource {
        SimulatedDataSource(seed: seed, clock: ImmediateSimulationClock(), maxTicks: maxTicks, insights: insights)
    }

    /// A real-time source whose telemetry plays out at `timeScale`× wall speed — for a running app.
    /// Pair with `bootstrap()` + `start()`.
    public static func live(
        seed: UInt64 = 42,
        timeScale: Double = 600,
        insights: any InsightsProviding = DeterministicInsightsProvider()
    ) -> SimulatedDataSource {
        SimulatedDataSource(seed: seed, clock: AcceleratedSimulationClock(timeScale: timeScale), maxTicks: nil, insights: insights)
    }

    /// Registers the fleet catalog and its default alert rules. Call once before ingesting, so the
    /// repositories return the fleet immediately (even before any telemetry).
    public func bootstrap() async throws {
        let entries = try await engine.descriptors().map { descriptor in
            DeviceCatalogEntry(descriptor: descriptor, rules: try DefaultAlertRules.rules(for: descriptor.assetKind))
        }
        await store.register(entries)
    }

    /// Drains the (bounded) telemetry stream into the store and returns when complete.
    public func ingestAll() async {
        await adapter.ingestAll()
    }

    /// Begins background ingestion (use with `live`).
    public func start() async {
        await adapter.start()
    }

    /// Stops background ingestion.
    public func stop() async {
        await adapter.stop()
    }

    /// Total readings folded into the store so far (diagnostics / tests).
    public func ingestedReadingCount() async -> Int {
        await store.ingestedReadingCount()
    }
}
