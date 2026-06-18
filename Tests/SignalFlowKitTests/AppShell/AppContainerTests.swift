import Foundation
import Testing
import DomainKit
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
        let container = AppContainer.preview()
        await container.start()
        await container.start() // second call is a no-op, not a double-bootstrap
        let assets = try await container.assets.allAssets()
        #expect(assets.count == 10)
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
