import AppIntents
import SnapshotKit

/// Opens the app on the **Dashboard** tab. `openAppWhenRun` foregrounds the app, then `perform()`
/// publishes the route to ``AppNavigationModel`` for `RootView` to act on.
public struct OpenDashboardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Dashboard"
    public static let description = IntentDescription("Opens SignalFlow on the fleet dashboard.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await AppNavigationModel.shared.request(.dashboard)
        return .result()
    }
}

/// Opens the app on the **Fleet** tab (the fleet-status list).
public struct OpenFleetStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Fleet Status"
    public static let description = IntentDescription("Opens SignalFlow on the fleet status list.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await AppNavigationModel.shared.request(.fleet)
        return .result()
    }
}

/// Opens the app on the **Alerts** tab.
public struct OpenCriticalAlertsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Critical Alerts"
    public static let description = IntentDescription("Opens SignalFlow on the active alerts console.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await AppNavigationModel.shared.request(.alerts)
        return .result()
    }
}
