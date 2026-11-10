import Foundation
import Synchronization
import Testing
import DomainKit
import SimulationKit
import PersistenceKit
@testable import DataKit
@testable import SignalFlowApp

@MainActor
@Suite("App container (composition root)")
struct AppContainerTests {

    @Test("Starting the container boots the data layer and exposes a working fleet")
    func startBootsFleet() async throws {
        let container = AppContainer.preview()
        await container.start()

        // bootstrap() runs inside start(), registering the catalog, so the fleet is queryable
        // immediately — independent of background ingestion.
        let assets = try await container.assets.allAssets()
        #expect(assets.count == 10)

        await container.stop() // clean, cancellation-safe teardown — must not hang
    }

    @Test("start() is idempotent")
    func startIsIdempotent() async throws {
        let persistence = CountingPersistence()
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))
        #expect(container.startupState == .notStarted)
        await container.start()
        await container.start() // second call is a no-op, not a double-bootstrap
        #expect(container.startupState == .ready)
        #expect(await persistence.loadCount == 1)
        #expect(try await container.assets.allAssets().count == 10)
        await container.stop()
    }

    @Test("Overlapping start() calls bootstrap exactly once")
    func concurrentStartsBootstrapOnce() async throws {
        // At launch `RootView.task` and the scene-phase `.active` handler both call start().
        let persistence = CountingPersistence()
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))
        async let first: Void = container.start()
        async let second: Void = container.start()
        _ = await (first, second)
        #expect(await persistence.loadCount == 1)
        await container.stop()
    }

    /// The bootstrap of the first start is held open, so every later request is made while an older
    /// one is still in flight. Order is fixed when each request is made, not when a task gets to run,
    /// so the outcome must match the last request: no scheduler luck involved.
    @Test("Requests apply in the order they were made, even while an older one is delayed",
          arguments: [
              [true, false, true],                 // active → background → active
              [false, true, false],                // background → active → background
              [true, true, false, true, false],    // duplicate start, stop during start, repeat
          ])
    func requestsApplyInRequestOrder(sequence: [Bool]) async throws {
        let gate = Latch()
        let persistence = CountingPersistence(holdRestoreUntil: gate)
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        var last: Task<Void, Never>?
        for wantsActive in sequence {
            last = wantsActive ? container.requestStart() : container.requestStop()
        }
        await gate.open()                       // let the oldest request finish only now
        await last?.value

        #expect(await container.source.isIngesting() == sequence.last)
        #expect(await persistence.loadCount == 1)
        await container.stop()
        #expect(await container.source.isIngesting() == false)
    }

    @Test("Cancelling a request's task doesn't withdraw or reorder the transition")
    func cancellationDoesNotWithdrawRequests() async throws {
        let gate = Latch()
        let persistence = CountingPersistence(holdRestoreUntil: gate)
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        let starting = container.requestStart()
        starting.cancel()                       // cancelled mid-bootstrap
        await gate.open()
        await starting.value
        #expect(await container.source.isIngesting())

        let stopping = container.requestStop()
        stopping.cancel()                       // cancelled during shutdown
        await stopping.value
        #expect(await container.source.isIngesting() == false)

        // A caller awaiting start() (like a view's `.task`) that gets cancelled doesn't abandon it.
        let caller = Task { await container.start() }
        caller.cancel()
        await caller.value
        await container.requestStop().value
        #expect(await container.source.isIngesting() == false)
        #expect(await persistence.loadCount == 1)
    }

    @Test("A failed restore doesn't block launch; the app runs on fresh telemetry")
    func restoreFailureStillStarts() async throws {
        let persistence = CountingPersistence(restoreErrors: [CocoaError(.fileReadCorruptFile)])
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        await container.start()
        #expect(try await container.assets.allAssets().count == 10) // catalog registered before restore
        #expect(await container.source.isIngesting())
        #expect(container.startupState == .degraded(.restoreFailed)) // usable, but reported

        // A later foreground doesn't retry the restore: by then live telemetry is newer than the snapshot.
        await container.stop()
        await container.start()
        #expect(await persistence.loadCount == 1)
        await container.stop()
    }

    // MARK: - Startup failure and recovery

    @Test("A failed bootstrap is reported, not recorded as done, and starts no ingestion")
    func failedBootstrapIsNotSuccess() async throws {
        let rules = RuleSwitch(failing: true)
        let container = AppContainer(source: rules.source())

        await container.start()
        #expect(container.startupState == .failed)
        #expect(await container.source.isIngesting() == false)
        #expect(try await container.assets.allAssets().isEmpty) // nothing half-registered
        await container.stop()
        #expect(await container.source.isIngesting() == false)
    }

    @Test("Starts already queued when a bootstrap fails don't retry it")
    func queuedStartsDontRetry() async throws {
        // At launch `onAppear` and the scene phase both request a start before either runs.
        let rules = RuleSwitch(failing: true)
        let container = AppContainer(source: rules.source())

        container.requestStart()
        container.requestStart()
        await container.requestStart().value
        #expect(rules.failedAttempts == 1)
        #expect(container.startupState == .failed)
        #expect(await container.source.isIngesting() == false)
    }

    @Test("A start requested after a failure retries, and recovers once the cause is gone")
    func retryRecovers() async throws {
        let rules = RuleSwitch(failing: true)
        let persistence = CountingPersistence()
        let container = AppContainer(source: rules.source(persistence: persistence))

        await container.start()
        #expect(container.startupState == .failed)
        await container.start()                     // still failing: a second, explicit attempt
        #expect(rules.failedAttempts == 2)
        #expect(container.startupState == .failed)

        rules.recover()
        await container.start()
        #expect(container.startupState == .ready)
        #expect(await container.source.isIngesting())
        #expect(try await container.assets.allAssets().count == 10)
        #expect(await persistence.loadCount == 1)

        await container.stop()                      // after success, later starts don't bootstrap again
        await container.start()
        #expect(await persistence.loadCount == 1)
        #expect(rules.failedAttempts == 2)
        await container.stop()
    }

    @Test("A background transition requested during a retry leaves ingestion stopped")
    func stopDuringRetryWins() async throws {
        let rules = RuleSwitch(failing: true)
        let started = Latch()
        let gate = Latch()
        let persistence = CountingPersistence(restoreStarted: started, holdRestoreUntil: gate)
        let container = AppContainer(source: rules.source(persistence: persistence))
        await container.start()
        #expect(container.startupState == .failed)

        rules.recover()
        container.requestStart()                    // the retry, held inside its restore…
        await started.wait()
        #expect(container.startupState == .starting)
        let stopping = container.requestStop()      // …while the app goes to the background
        await gate.open()
        await stopping.value

        #expect(container.startupState == .ready)   // the retry completed, in order
        #expect(await container.source.isIngesting() == false)
        await container.start()                     // and the next foreground just resumes
        #expect(await container.source.isIngesting())
        #expect(await persistence.loadCount == 1)
        await container.stop()
    }

    @Test("A bootstrap cancelled by its dependency is neither a failure nor a success")
    func cancelledBootstrapIsNotRecorded() async throws {
        let persistence = CountingPersistence(restoreErrors: [CancellationError()])
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        await container.start()
        #expect(container.startupState == .notStarted)
        #expect(await container.source.isIngesting() == false)

        await container.start()                     // the next start bootstraps from scratch
        #expect(container.startupState == .ready)
        #expect(await container.source.isIngesting())
        #expect(await persistence.loadCount == 2)
        await container.stop()
    }

    @Test("Running without the on-disk store is reported as degraded")
    func persistenceUnavailableIsDegraded() async throws {
        let container = AppContainer(source: .deterministic(seed: 42, maxTicks: 5), persistenceUnavailable: true)
        await container.start()
        #expect(container.startupState == .degraded(.persistenceUnavailable))
        #expect(await container.source.isIngesting())
        await container.stop()
    }

    @Test("The container exposes the same ports the features consume")
    func exposesDomainPorts() async throws {
        let container = AppContainer.preview()
        await container.start()
        // Drive a domain use case purely through the container's ports.
        let overview = try await FetchFleetOverviewUseCase(
            assets: container.assets, devices: container.devices, alerts: container.alerts
        )()
        #expect(overview.count == 10)
        await container.stop()
    }
}

/// A `PersistenceStoring` that persists nothing and counts restores, to observe bootstrap behaviour.
/// It can hold the restore open to keep a start operation in flight.
private actor CountingPersistence: PersistenceStoring {
    private(set) var loadCount = 0
    private var restoreErrors: [any Error]
    private let started: Latch?
    private let gate: Latch?

    /// Each restore throws the next of `restoreErrors`, then restores succeed. `restoreStarted` opens
    /// when a restore begins; `holdRestoreUntil` keeps it (and so its start) suspended until it opens.
    init(restoreErrors: [any Error] = [], restoreStarted started: Latch? = nil, holdRestoreUntil gate: Latch? = nil) {
        self.restoreErrors = restoreErrors
        self.started = started
        self.gate = gate
    }

    func loadSnapshot() async throws -> PersistedSnapshot {
        loadCount += 1
        await started?.open()
        await gate?.wait()
        if !restoreErrors.isEmpty { throw restoreErrors.removeFirst() }
        return PersistedSnapshot(assets: [], devices: [], latestReadings: [], events: [], alerts: [], insights: [])
    }
    func upsertCatalog(assets: [Asset], devices: [Device]) async throws {}
    func appendReadings(_ readings: [TelemetryReading]) async throws {}
    func appendEvents(_ events: [DeviceEvent]) async throws {}
    func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) async throws {}
    func appendInsight(_ insight: InsightRecord) async throws {}
    func trimHistory() async throws -> Bool { false }
}

/// Alert rules that fail on demand — the only way to make the catalog, and so the bootstrap, fail.
/// A failing attempt throws on its first descriptor, so `failedAttempts` counts bootstrap attempts.
private final class RuleSwitch: Sendable {
    private let failing: Atomic<Bool>
    private let failures = Atomic<Int>(0)

    init(failing: Bool) { self.failing = Atomic(failing) }

    var failedAttempts: Int { failures.load(ordering: .relaxed) }
    func recover() { failing.store(false, ordering: .relaxed) }

    func rules(for kind: AssetKind) throws -> [AlertRule] {
        if failing.load(ordering: .relaxed) {
            failures.add(1, ordering: .relaxed)
            throw DomainError.insufficientData
        }
        return try DefaultAlertRules.rules(for: kind)
    }

    func source(persistence: (any PersistenceStoring)? = nil) -> SimulatedDataSource {
        SimulatedDataSource(
            seed: 42, clock: ImmediateSimulationClock(), maxTicks: 5,
            insights: DeterministicInsightsProvider(), persistence: persistence, alertRules: rules(for:)
        )
    }
}
