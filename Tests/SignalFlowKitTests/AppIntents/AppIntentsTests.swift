import Testing
import Foundation
import AppIntents
import DomainKit
import PersistenceKit
import SnapshotKit
@testable import AppIntentsKit

/// Serialized because the navigation model and the App Intents dependency container are process-global.
@MainActor
@Suite("App Intents", .serialized)
struct AppIntentsTests {

    // MARK: - Route generation / deep-link handling

    @Test("Every route generates and round-trips through its signalflow:// URL")
    func routeGeneration() {
        #expect(DeepLinkRoute.dashboard.url.absoluteString == "signalflow://dashboard")
        #expect(DeepLinkRoute.fleet.url.absoluteString == "signalflow://fleet")
        #expect(DeepLinkRoute.alerts.url.absoluteString == "signalflow://alerts")
        #expect(DeepLinkRoute.insights.url.absoluteString == "signalflow://insights")

        for route in DeepLinkRoute.allCases {
            #expect(DeepLinkRoute(url: route.url) == route)
        }
        #expect(DeepLinkRoute(url: URL(string: "https://example.com/alerts")!) == nil)
        #expect(DeepLinkRoute(url: URL(string: "signalflow://unknown")!) == nil)
    }

    @Test("Open intents publish the matching route to the navigation model")
    func openIntentsRequestRoutes() async throws {
        AppNavigationModel.shared.pendingRoute = nil

        _ = try await OpenDashboardIntent().perform()
        #expect(AppNavigationModel.shared.pendingRoute == .dashboard)

        _ = try await OpenFleetStatusIntent().perform()
        #expect(AppNavigationModel.shared.pendingRoute == .fleet)

        _ = try await OpenCriticalAlertsIntent().perform()
        #expect(AppNavigationModel.shared.pendingRoute == .alerts)

        AppNavigationModel.shared.pendingRoute = nil
    }

    // MARK: - Summary generation

    @Test("Spoken summary reads naturally across fleet states")
    func summaryGeneration() {
        #expect(FleetSummary.empty.spokenSummary == "No devices are reporting yet.")

        let healthy = FleetSummary(online: 10, warning: 0, critical: 0, offline: 0, lastUpdated: nil)
        #expect(healthy.spokenSummary == "10 of 10 devices online.")

        let mixed = FleetSummary(online: 6, warning: 2, critical: 1, offline: 1, lastUpdated: nil)
        #expect(mixed.spokenSummary == "6 of 10 devices online, 1 critical, 2 warning, 1 offline.")
    }

    // MARK: - Intent data provider behavior

    @Test("Persisted provider aggregates the snapshot it reads through SnapshotKit")
    func providerReadsPersistedSnapshot() async throws {
        let assetID = AssetID()
        let store = PersistenceStore(modelContainer: try PersistenceController.makeInMemoryContainer())
        let asset = try Asset(id: assetID, name: "Fleet A", kind: .refrigeratedTruck, deviceIDs: [])
        let online = try Device(assetID: assetID, name: "D1", connectivity: ConnectivityStatus(state: .online))
        let down = try Device(assetID: assetID, name: "D2", connectivity: ConnectivityStatus(state: .offline))
        try await store.upsertCatalog(assets: [asset], devices: [online, down])

        let provider = PersistedFleetSummaryProvider(reader: WidgetSnapshotReader(store: store))
        let summary = try await provider.currentSummary()

        #expect(summary.online == 1)
        #expect(summary.offline == 1)
        #expect(summary.total == 2)
    }

    @Test("Show Fleet Summary intent resolves its dependency and returns the spoken summary")
    func showFleetSummaryIntentUsesProvider() async throws {
        let stub = FleetSummary(online: 4, warning: 1, critical: 0, offline: 0, lastUpdated: nil)
        AppIntentsEnvironment.fleetSummaryProvider = StubFleetSummaryProvider(summary: stub)
        defer { AppIntentsEnvironment.fleetSummaryProvider = PersistedFleetSummaryProvider() }

        let value = try await ShowFleetSummaryIntent().perform().value
        #expect(value == stub.spokenSummary)
    }
}

private struct StubFleetSummaryProvider: FleetSummaryProviding {
    let summary: FleetSummary
    func currentSummary() async throws -> FleetSummary { summary }
}
