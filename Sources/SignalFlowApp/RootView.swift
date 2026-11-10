import SwiftUI
import DomainKit
import DesignSystemKit
import FeatureDashboard
import FeatureFleet
import FeatureDeviceDetail
import FeatureInsights
import FeatureAlerts
import SnapshotKit
import AppIntentsKit

/// The root user-facing surface: a Dashboard tab and a Fleet tab, with value-based navigation from a
/// fleet row to its Device Detail.
///
/// It reads its data through the injected ``AppContainer``'s `DomainKit` ports — it never names a
/// concrete data type. Lifecycle (starting ingestion) is driven from `.task`, and also from the
/// app's scene phase, so the work is tied to the view being on screen.
///
/// Tab selection is bound so both **deep links** (`signalflow://dashboard|fleet|alerts|insights`, via
/// `.onOpenURL`) and **App Intents** (via the shared ``AppNavigationModel``) can route the user
/// straight to the right surface.
public struct RootView: View {
    private let container: AppContainer
    @State private var fleetPath: [DeviceID] = []
    @State private var selection: Tab = .dashboard
    @State private var navigation = AppNavigationModel.shared
    @State private var dismissedDegradation: StartupState.Degradation?

    /// Tabs, with stable tags so routes can select one.
    private enum Tab: Hashable { case dashboard, fleet, alerts, insights }

    private func tab(for route: DeepLinkRoute) -> Tab {
        switch route {
        case .dashboard: .dashboard
        case .fleet: .fleet
        case .alerts: .alerts
        case .insights: .insights
        }
    }

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        // The stack gives the content one stable identity, so switching between the failure screen and
        // the tabs doesn't re-run `onAppear` (which would be an automatic start request) or the tasks.
        ZStack { content }
            .tint(.signalFlowAccent)
            // Follows the system appearance (Light **and** Dark). Status/severity hues are system semantic
            // colours, and the accent + card surfaces are appearance-adaptive, so the monitoring surfaces stay
            // legible and accessible in both modes.
            // Synchronous request on appear (also starts previews, which have no scene-phase handler).
            .onAppear { container.requestStart() }
            .task { await container.observeCriticalAlertActivity() }
            .task { await container.observeWatchSync() }
            .task {
                // A route an intent requested before this view appeared (e.g. cold launch from Shortcuts).
                if let route = navigation.pendingRoute {
                    selection = tab(for: route)
                    navigation.pendingRoute = nil
                }
            }
            .onChange(of: navigation.pendingRoute) { _, route in
                // App Intents (Open Dashboard / Fleet Status / Critical Alerts) drive navigation here.
                if let route {
                    selection = tab(for: route)
                    navigation.pendingRoute = nil
                }
            }
            .onOpenURL { url in
                // Widgets, Spotlight, App Intents, and Live Activities arrive as signalflow:// URLs.
                switch DeepLink(url: url) {
                case .route(let route):
                    selection = tab(for: route)
                case .device(let deviceID):
                    // A Live Activity tap deep-links to its device's detail screen.
                    selection = .fleet
                    fleetPath = [deviceID]
                case nil:
                    break
                }
            }
    }

    /// A failed startup replaces the tabs: with no catalog there is nothing they could show.
    @ViewBuilder private var content: some View {
        if container.startupState == .failed {
            ContentUnavailableView {
                Label(loc("SignalFlow couldn't start"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(loc("Something went wrong while preparing your fleet."))
            } actions: {
                Button(loc("Try Again")) { container.requestStart() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack {
                DashboardScreen(
                    assets: container.assets,
                    devices: container.devices,
                    alerts: container.alerts,
                    events: container.events,
                    onShowAlerts: { selection = .alerts }
                )
            }
            .safeAreaInset(edge: .bottom) { degradedNotice }
            .tabItem { Label(loc("Overview"), systemImage: "square.grid.2x2.fill") }
            .tag(Tab.dashboard)

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
            .tabItem { Label(loc("Devices"), systemImage: "list.bullet.rectangle.fill") }
            .tag(Tab.fleet)

            NavigationStack {
                AlertsScreen(
                    assets: container.assets,
                    devices: container.devices,
                    alerts: container.alerts,
                    alertHistory: container.alertHistory
                )
            }
            .tabItem { Label(loc("Alerts"), systemImage: "bell.fill") }
            .tag(Tab.alerts)

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
            .tabItem { Label(loc("Insights"), systemImage: "sparkles") }
            .tag(Tab.insights)
        }
    }

    /// A discreet, dismissible note on the Overview tab while the app runs degraded.
    @ViewBuilder private var degradedNotice: some View {
        if case .degraded(let reason) = container.startupState, dismissedDegradation != reason {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(reason.message)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(loc("Dismiss"), systemImage: "xmark") { dismissedDegradation = reason }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

private extension StartupState.Degradation {
    var message: String {
        switch self {
        case .persistenceUnavailable: loc("Data isn't being saved on this device.")
        case .restoreFailed: loc("Saved data couldn't be restored. Showing live data only.")
        }
    }
}

#Preview {
    RootView(container: .preview())
}
