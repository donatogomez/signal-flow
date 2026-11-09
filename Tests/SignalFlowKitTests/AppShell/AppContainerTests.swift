import Foundation
import Testing
import DomainKit
import DataKit
import PersistenceKit
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
        await container.start()
        await container.start() // second call is a no-op, not a double-bootstrap
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
        let persistence = CountingPersistence(failRestore: true)
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        await container.start()
        #expect(try await container.assets.allAssets().count == 10) // catalog registered before restore
        #expect(await container.source.isIngesting())

        // A later foreground doesn't retry the restore: by then live telemetry is newer than the snapshot.
        await container.stop()
        await container.start()
        #expect(await persistence.loadCount == 1)
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
    private let failRestore: Bool
    private let gate: Latch?

    /// `holdRestoreUntil` keeps the restore (and so the first start) suspended until the gate opens.
    init(failRestore: Bool = false, holdRestoreUntil gate: Latch? = nil) {
        self.failRestore = failRestore
        self.gate = gate
    }

    func loadSnapshot() async throws -> PersistedSnapshot {
        loadCount += 1
        await gate?.wait()
        if failRestore { throw CocoaError(.fileReadCorruptFile) }
        return PersistedSnapshot(assets: [], devices: [], latestReadings: [], events: [], alerts: [], insights: [])
    }
    func upsertCatalog(assets: [Asset], devices: [Device]) async throws {}
    func appendReadings(_ readings: [TelemetryReading]) async throws {}
    func appendEvents(_ events: [DeviceEvent]) async throws {}
    func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) async throws {}
    func appendInsight(_ insight: InsightRecord) async throws {}
}
