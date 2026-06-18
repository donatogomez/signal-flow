import SwiftUI
import DomainKit
import DataKit
import FeatureDashboard
import FeatureFleet
import FeatureDeviceDetail

/// The composition root for the user-facing experience.
///
/// This is the **only** layer that knows a concrete data source exists. It builds a `DataKit`
/// `SimulatedDataSource`, starts ingestion, and injects the resulting `DomainKit` ports into the
/// feature screens. The features themselves never see DataKit or SimulationKit — they receive
/// `any AssetRepository`, `any TelemetryRepository`, … and nothing more.
///
/// A future `@main App` simply hosts this view; keeping the composition here means the app shell is a
/// thin wrapper rather than a place where wiring accumulates.
public struct RootView: View {
    @State private var source: SimulatedDataSource
    @State private var fleetPath: [DeviceID] = []
    @State private var didStart = false

    /// - Parameter source: The data layer. Defaults to a real-time simulated source; previews and
    ///   tests can inject a deterministic one.
    public init(source: SimulatedDataSource = .live(seed: 42, timeScale: 600)) {
        _source = State(initialValue: source)
    }

    public var body: some View {
        TabView {
            NavigationStack {
                DashboardScreen(
                    assets: source.assets,
                    devices: source.devices,
                    alerts: source.alerts,
                    events: source.events
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            NavigationStack(path: $fleetPath) {
                FleetScreen(
                    assets: source.assets,
                    devices: source.devices,
                    alerts: source.alerts,
                    onOpenDevice: { fleetPath.append($0) }
                )
                .navigationDestination(for: DeviceID.self) { deviceID in
                    DeviceDetailScreen(
                        deviceID: deviceID,
                        devices: source.devices,
                        telemetry: source.telemetry,
                        alerts: source.alerts,
                        events: source.events
                    )
                }
            }
            .tabItem { Label("Fleet", systemImage: "list.bullet.rectangle.fill") }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            try? await source.bootstrap()
            await source.start()
        }
    }
}

#Preview {
    // Deterministic source so the preview fills with reproducible telemetry quickly.
    RootView(source: .deterministic(seed: 42, maxTicks: 80))
}
