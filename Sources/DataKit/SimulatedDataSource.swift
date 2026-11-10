import DomainKit
import SimulationKit
import PersistenceKit

/// What ``SimulatedDataSource/bootstrap()`` restored from persistence.
public enum RestoreOutcome: Sendable, Equatable {
    /// No persistence is configured, so the session starts from the catalog by design.
    case notConfigured
    /// The last persisted snapshot was loaded into the store.
    case restored
    /// Loading the snapshot failed. The catalog is registered and the session continues on fresh
    /// telemetry, without the previously saved state (degraded, not fatal).
    case failed
}

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
    public let alertHistory: any AlertHistoryProviding
    public let events: any EventRepository
    public let insights: any InsightsProviding

    private let store: InMemoryTelemetryStore
    private let engine: SimulationEngineActor
    private let adapter: SimulationTelemetryAdapter
    private let persistence: (any PersistenceStoring)?
    private let coordinator: PersistenceCoordinator?
    private let alertRules: @Sendable (AssetKind) throws -> [AlertRule]

    /// `alertRules` is a test seam: the default rules are built from constant thresholds, so a
    /// catalog failure can only be injected.
    init(
        seed: UInt64,
        clock: any SimulationClock,
        maxTicks: Int?,
        insights: any InsightsProviding,
        persistence: (any PersistenceStoring)? = nil,
        alertRules: @escaping @Sendable (AssetKind) throws -> [AlertRule] = DefaultAlertRules.rules(for:)
    ) {
        let store = InMemoryTelemetryStore()
        let engine = SimulationFleet.standard(seed: seed, clock: clock, maxTicks: maxTicks)
        self.store = store
        self.engine = engine
        self.persistence = persistence
        self.alertRules = alertRules

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
        self.alertHistory = StoreAlertHistoryRepository(store: store)
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
    ///
    /// Failures are split by what the session can still do:
    /// - Building the catalog fails → **throws**. Nothing is registered, so the call can be repeated.
    /// - The restore fails → logged and reported as ``RestoreOutcome/failed``; the catalog stays
    ///   registered and the session can run on fresh telemetry.
    /// - Cancellation is rethrown, never reported as a failed restore.
    @discardableResult
    public func bootstrap() async throws -> RestoreOutcome {
        let entries = try await engine.descriptors().map { descriptor in
            DeviceCatalogEntry(descriptor: descriptor, rules: try alertRules(descriptor.assetKind))
        }
        await store.register(entries)

        guard let persistence else { return .notConfigured }
        let snapshot: PersistedSnapshot
        do {
            snapshot = try await persistence.loadSnapshot()
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            Log.persistence.error("Restore failed; continuing without saved state: \(String(describing: error), privacy: .private)")
            return .failed
        }
        await store.loadRestoredState(
            assets: snapshot.assets, devices: snapshot.devices,
            latestReadings: snapshot.latestReadings, events: snapshot.events,
            alerts: snapshot.alerts, insights: snapshot.insights
        )
        return .restored
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

    /// Whether an ingestion session is active, i.e. started and not yet stopped (diagnostics / tests).
    public func isIngesting() async -> Bool {
        await adapter.isRunning
    }
}
