import SimulationKit

/// Consumes a `SimulationEngineActor`'s merged telemetry stream and folds every item into the
/// `InMemoryTelemetryStore`. This is the one place that touches SimulationKit's stream; everything
/// downstream sees only the store and the domain ports.
///
/// Concurrency:
/// - **Structured** ingestion (`ingestAll`) runs under the caller's task — ideal for bounded,
///   deterministic test runs.
/// - **Managed** ingestion (`start`/`stop`) owns a single background `Task`, stored here so it can be
///   cancelled. The closure captures only the two actors (not `self`), so there is no retain cycle,
///   and `deinit` cancels the task to guarantee it never leaks.
public actor SimulationTelemetryAdapter {
    private let engine: SimulationEngineActor
    private let store: InMemoryTelemetryStore
    private var task: Task<Void, Never>?

    public init(engine: SimulationEngineActor, store: InMemoryTelemetryStore) {
        self.engine = engine
        self.store = store
    }

    /// Drains the fleet stream to completion (or until the surrounding task is cancelled). Use with a
    /// bounded clock (`maxTicks`) for deterministic runs.
    public func ingestAll() async {
        for await item in await engine.makeFleetStream() {
            await store.ingest(item)
        }
    }

    /// Starts background ingestion. Idempotent — a second call while running is a no-op.
    public func start() {
        guard task == nil else { return }
        let engine = self.engine
        let store = self.store
        task = Task {
            for await item in await engine.makeFleetStream() {
                await store.ingest(item)
            }
        }
    }

    /// Stops background ingestion promptly. Cancelling the task ends the `for await` (AsyncStream is
    /// cancellation-aware), which terminates the underlying fleet stream via `onTermination`.
    public func stop() {
        task?.cancel()
        task = nil
    }

    public var isRunning: Bool { task != nil }

    deinit { task?.cancel() }
}
