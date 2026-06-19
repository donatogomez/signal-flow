import WidgetKit
import SwiftUI
import WidgetSupportKit

/// The widget extension's entry point — a thin `@main` shell, exactly like `SignalFlowHost` is for the
/// app. All widget logic and views live in the `WidgetSupportKit` SwiftPM library, so they're built and
/// unit-tested from the package; this file just declares the bundle of widgets the extension vends.
@main
struct SignalFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        FleetStatusWidget()
        CriticalAlertsWidget()
    }
}
