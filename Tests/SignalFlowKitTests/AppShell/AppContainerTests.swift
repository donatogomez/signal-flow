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

    /// The scene-phase handler issues every transition as its own unstructured `Task`, so this drives the
    /// container exactly that way: a burst of back-to-back requests that overlap each other's bootstrap,
    /// start and stop. Whatever the interleaving, the requests must apply in the order they were made.
    @Test("Rapid scene-phase transitions apply in request order and settle on the last one",
          arguments: [true, false])
    func rapidTransitionsSettleOnLastRequest(endActive: Bool) async throws {
        let persistence = CountingPersistence()
        let container = AppContainer(source: .persisted(seed: 42, maxTicks: 5, persistence: persistence))

        var requests: [Task<Void, Never>] = []
        for _ in 0..<25 {
            requests.append(Task { await container.start() })   // .active
            requests.append(Task { await container.stop() })    // .background
        }
        if endActive { requests.append(Task { await container.start() }) }
        for request in requests { await request.value }

        #expect(await container.source.isIngesting() == endActive)
        #expect(await persistence.loadCount == 1)
        await container.stop()
        #expect(await container.source.isIngesting() == false)
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
private actor CountingPersistence: PersistenceStoring {
    private(set) var loadCount = 0
    private let failRestore: Bool

    init(failRestore: Bool = false) { self.failRestore = failRestore }

    func loadSnapshot() async throws -> PersistedSnapshot {
        loadCount += 1
        if failRestore { throw CocoaError(.fileReadCorruptFile) }
        return PersistedSnapshot(assets: [], devices: [], latestReadings: [], events: [], alerts: [], insights: [])
    }
    func upsertCatalog(assets: [Asset], devices: [Device]) async throws {}
    func appendReadings(_ readings: [TelemetryReading]) async throws {}
    func appendEvents(_ events: [DeviceEvent]) async throws {}
    func replaceActiveAlerts(_ alerts: [Alert], forDevice deviceID: DeviceID) async throws {}
    func appendInsight(_ insight: InsightRecord) async throws {}
}
