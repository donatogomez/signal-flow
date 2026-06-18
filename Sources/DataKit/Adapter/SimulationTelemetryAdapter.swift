import SimulationKit

/// Consumes a `SimulationEngineActor`'s merged telemetry stream and folds every item into the
/// `InMemoryTelemetryStore`. This is the one place that touches SimulationKit's stream; everything
/// downstream sees only the store and the domain ports.
///
/// An optional `sink` is invoked for each item *after* it lands in the store — used to mirror writes
/// to persistence without coupling the adapter to PersistenceKit.
///
/// Concurrency:
/// - **Structured** ingestion (`ingestAll`) runs under the caller's task — ideal for bounded,
///   deterministic test runs.
/// - **Managed** ingestion (`start`/`stop`) owns a single background `Task`, stored here so it can be
///   cancelled. The closure captures only Sendable values (not `self`), so there is no retain cycle.
/// - **`stop()` awaits the loop's completion** after cancelling, so once it returns the cancelled
///   session is provably finished and can no longer mutate the store. `deinit` cancels as a backstop.
public actor SimulationTelemetryAdapter {
    private let engine: SimulationEngineActor
    private let store: InMemoryTelemetryStore
    private let sink: (@Sendable (DeviceTelemetry) async -> Void)?
    private var task: Task<Void, Never>?

    public init(
        engine: SimulationEngineActor,
        store: InMemoryTelemetryStore,
        sink: (@Sendable (DeviceTelemetry) async -> Void)? = nil
    ) {
        self.engine = engine
        self.store = store
        self.sink = sink
    }

    /// Drains the fleet stream to completion (or until the surrounding task is cancelled). Use with a
    /// bounded clock (`maxTicks`) for deterministic runs.
    public func ingestAll() async {
        await ingestLoop(engine: engine, store: store, sink: sink)
    }

    /// Starts background ingestion. Idempotent — a second call while running is a no-op.
    public func start() {
        guard task == nil else { return }
        let engine = self.engine
        let store = self.store
        let sink = self.sink
        task = Task { await ingestLoop(engine: engine, store: store, sink: sink) }
    }

    /// Stops background ingestion and **waits for the loop to finish**.
    ///
    /// Cancelling the task ends the `for await` (AsyncStream is cancellation-aware), which terminates
    /// the underlying fleet stream via `onTermination`. Awaiting `task.value` then guarantees that no
    /// further telemetry from this session can be written once `stop()` returns — the property the
    /// CI-stable cancellation test relies on. Concurrent/duplicate calls are safe and idempotent.
    public func stop() async {
        guard let task else { return }
        task.cancel()
        await task.value
        self.task = nil
    }

    public var isRunning: Bool { task != nil }

    deinit { task?.cancel() }
}

/// The ingestion loop, file-private so the background `Task` captures only Sendable values (no `self`)
/// — avoiding a retain cycle and keeping the loop off the adapter's executor. It checks for
/// cancellation **before** each store mutation, and exits when the stream terminates on cancellation.
private func ingestLoop(
    engine: SimulationEngineActor,
    store: InMemoryTelemetryStore,
    sink: (@Sendable (DeviceTelemetry) async -> Void)?
) async {
    for await item in await engine.makeFleetStream() {
        if Task.isCancelled { break }
        await store.ingest(item)
        if let sink { await sink(item) }
    }
}
