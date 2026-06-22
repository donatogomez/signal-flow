import SwiftUI
import WatchSupportKit

/// The watchOS companion's entry point — a thin `@main` shell, like `SignalFlowHost` is for iOS. All
/// screens and models live in `WatchSupportKit` (built and unit-tested from the package); this file just
/// hosts the root view and starts the WatchConnectivity sync. The watch renders snapshots synced from the
/// iPhone and never runs the data engine.
@main
struct SignalFlowWatchApp: App {
    @State private var coordinator = WatchSyncCoordinator()

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: coordinator.store)
                .task { await coordinator.start() }
        }
    }
}
