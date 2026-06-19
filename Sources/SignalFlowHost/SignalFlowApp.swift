import SwiftUI
import SignalFlowApp
import AppIntentsKit

/// The application entry point.
///
/// Deliberately tiny: it builds the composition root (``AppContainer``), hosts ``RootView``, and ties
/// the data layer's lifecycle to the scene phase. All wiring lives in `AppContainer`, so this shell
/// stays a few lines — and the identical file hosts the app whether the target is this SwiftPM
/// executable or an Xcode iOS app target.
@main
struct SignalFlowApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // App Intents run in this process; register their dependencies once at launch so `@Dependency`
        // resolves the persisted-data provider for Shortcuts/Siri invocations.
        AppIntentsBootstrap.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await container.start() }
            case .background:
                Task { await container.stop() }
            default:
                break
            }
        }
    }
}
