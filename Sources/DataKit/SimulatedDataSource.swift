import DomainKit
import SimulationKit
import PersistenceKit

/// The DataKit composition root for a simulation-backed data layer.
///
/// It assembles the store, the simulated fleet, the ingestion adapter, the `DomainKit`-typed
/// repositories, and (optionally) a persistence coordinator. It exposes only domain ports plus
/// lifecycle controls, so callers never name a SimulationKit or PersistenceKit type — the bridge is
/// fully encapsulated.
///
/// **Offline-first.** When a `PersistenceStoring` is supplied, `bootstrap()` restores the last
/// persisted snapshot into the in-memory store, then the simulation continues on top, mirroring new
/// telemetry, events, alerts, and insights to durable storage off the hot path.
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
    private let persistence: (any PersistenceStoring)?
    private let coordinator: PersistenceCoordinator?

    init(
        seed: UInt64,
        clock: any SimulationClock,
        maxTicks: Int?,
        insights: any InsightsProviding,
        persistence: (any PersistenceStoring)? = nil
    ) {
        let store = InMemoryTelemetryStore()
        let engine = SimulationFleet.standard(seed: seed, clock: clock, maxTicks: maxTicks)
        self.store = store
        self.engine = engine
        self.persistence = persistence

        if let persistence {
            let coordinator = PersistenceCoordinator(persistence: persistence, store: store)
            self.coordinator = coordinator
            self.adapter = SimulationTelemetryAdapter(engine: engine, store: store) { item in
                await coordinator.enqueue(item)
            }
            self.insights = PersistingInsightsProvider(base: insights, persistence: persistence, store: store)
        } else {
            self.coordinator = nil
            self.adapter = SimulationTelemetryAdapter(engine: engine, store: store)
            self.insights = insights
        }

        self.assets = StoreAssetRepository(store: store)
        self.devices = StoreDeviceRepository(store: store)
        self.telemetry = StoreTelemetryRepository(store: store)
        self.alerts = StoreAlertRepository(store: store)
        self.events = StoreEventRepository(store: store)
    }

    /// A reproducible source that produces `maxTicks` of telemetry as fast as possible — for tests and
    /// previews. The insight provider is injectable so the composition root can supply a Foundation
    /// Models provider; it defaults to the deterministic one.
    public static func deterministic(
        seed: UInt64 = 42,
        maxTicks: Int = 120,
        insights: any InsightsProviding = DeterministicInsightsProvider()
    ) -> SimulatedDataSource {
        SimulatedDataSource(seed: seed, clock: ImmediateSimulationClock(), maxTicks: maxTicks, insights: insights)
    }

    /// A real-time source whose telemetry plays out at `timeScale`× wall speed — for a running app.
    public static func live(
        seed: UInt64 = 42,
        timeScale: Double = 600,
        insights: any InsightsProviding = DeterministicInsightsProvider(),
        persistence: (any PersistenceStoring)? = nil
    ) -> SimulatedDataSource {
        SimulatedDataSource(
            seed: seed, clock: AcceleratedSimulationClock(timeScale: timeScale),
            maxTicks: nil, insights: insights, persistence: persistence
        )
    }

    /// A deterministic, persistence-backed source — for restoration tests. Pairs a bounded immediate
    /// clock with an injected `PersistenceStoring`.
    public static func persisted(
        seed: UInt64 = 42,
        maxTicks: Int = 120,
        insights: any InsightsProviding = DeterministicInsightsProvider(),
        persistence: any PersistenceStoring
    ) -> SimulatedDataSource {
        SimulatedDataSource(
            seed: seed, clock: ImmediateSimulationClock(),
            maxTicks: maxTicks, insights: insights, persistence: persistence
        )
    }

    /// Registers the fleet catalog and its default alert rules, then — if persistence is present —
    /// restores the last persisted snapshot on top, so the fleet is queryable with real data the
    /// instant the app opens.
    public func bootstrap() async throws {
        let entries = try await engine.descriptors().map { descriptor in
            DeviceCatalogEntry(descriptor: descriptor, rules: try DefaultAlertRules.rules(for: descriptor.assetKind))
        }
        await store.register(entries)

        if let persistence {
            let snapshot = try await persistence.loadSnapshot()
            await store.loadRestoredState(
                assets: snapshot.assets, devices: snapshot.devices,
                latestReadings: snapshot.latestReadings, events: snapshot.events,
                alerts: snapshot.alerts, insights: snapshot.insights
            )
        }
    }

    /// Drains the (bounded) telemetry stream into the store and returns when complete, then flushes
    /// anything buffered for persistence.
    public func ingestAll() async {
        await adapter.ingestAll()
        await coordinator?.flush()
    }

    /// Begins background ingestion and periodic persistence flushing (use with `live`).
    public func start() async {
        await adapter.start()
        await coordinator?.startPeriodicFlush()
    }

    /// Begins background ingestion and returns only once the first reading has been ingested, then
    /// starts periodic persistence flushing. Deterministic startup — no polling, no sleeps.
    public func startAndWaitUntilFirstIngestion() async {
        await adapter.startAndWaitUntilFirstIngestion()
        await coordinator?.startPeriodicFlush()
    }

    /// Stops background ingestion and performs a final persistence flush.
    public func stop() async {
        await adapter.stop()
        await coordinator?.stopAndFlush()
    }

    /// Forces a persistence flush (diagnostics / tests).
    public func flushPersistence() async {
        await coordinator?.flush()
    }

    /// Total readings folded into the store so far (diagnostics / tests).
    public func ingestedReadingCount() async -> Int {
        await store.ingestedReadingCount()
    }
}
