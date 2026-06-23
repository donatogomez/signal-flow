import WidgetKit
import SwiftUI
import WatchWidgetSupportKit

/// The watchOS widget extension's entry point — a thin `@main` shell, exactly like
/// `SignalFlowWatchApp` is for the watch app. All complication / Smart Stack logic and views live in the
/// `WatchWidgetSupportKit` SwiftPM library (built and unit-tested from the package); this file just
/// declares the bundle the extension vends.
@main
struct SignalFlowWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        FleetComplication()
    }
}
