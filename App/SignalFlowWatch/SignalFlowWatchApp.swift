import SwiftUI
import WatchSupportKit

/// The watchOS companion's entry point — a thin `@main` shell, like `SignalFlowHost` is for iOS. All
/// screens and models live in `WatchSupportKit` (built and unit-tested from the package); this file
/// just hosts the root view. The watch reads persisted fleet snapshots and never runs the data engine.
@main
struct SignalFlowWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
