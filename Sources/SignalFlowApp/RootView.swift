import SwiftUI
import DomainKit
import FeatureDashboard
import FeatureFleet
import FeatureDeviceDetail
import FeatureInsights
import FeatureAlerts

/// The root user-facing surface: a Dashboard tab and a Fleet tab, with value-based navigation from a
/// fleet row to its Device Detail.
///
/// It reads its data through the injected ``AppContainer``'s `DomainKit` ports — it never names a
/// concrete data type. Lifecycle (starting ingestion) is driven from `.task`, and also from the
/// app's scene phase, so the work is tied to the view being on screen.
public struct RootView: View {
    private let container: AppContainer
    @State private var fleetPath: [DeviceID] = []

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        TabView {
            NavigationStack {
                DashboardScreen(
                    assets: container.assets,
                    devices: container.devices,
                    alerts: container.alerts,
                    events: container.events
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            NavigationStack(path: $fleetPath) {
                FleetScreen(
                    assets: container.assets,
                    devices: container.devices,
                    alerts: container.alerts,
                    onOpenDevice: { fleetPath.append($0) }
                )
                .navigationDestination(for: DeviceID.self) { deviceID in
                    DeviceDetailScreen(
                        deviceID: deviceID,
                        devices: container.devices,
                        telemetry: container.telemetry,
                        alerts: container.alerts,
                        events: container.events
                    )
                }
            }
            .tabItem { Label("Fleet", systemImage: "list.bullet.rectangle.fill") }

            NavigationStack {
                AlertsScreen(
                    assets: container.assets,
                    devices: container.devices,
                    alerts: container.alerts,
                    alertHistory: container.alertHistory
                )
            }
            .tabItem { Label("Alerts", systemImage: "bell.fill") }

            NavigationStack {
                InsightsScreen(
                    assets: container.assets,
                    devices: container.devices,
                    telemetry: container.telemetry,
                    alerts: container.alerts,
                    events: container.events,
                    insights: container.insights
                )
            }
            .tabItem { Label("Insights", systemImage: "sparkles") }
        }
        .task { await container.start() }
    }
}

#Preview {
    RootView(container: .preview())
}
