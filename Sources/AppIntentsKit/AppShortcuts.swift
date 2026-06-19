import AppIntents

/// Exposes the intents to **Shortcuts, Spotlight, and Siri** automatically — no per-user setup.
///
/// Declaring an `AppShortcutsProvider` makes these four actions show up in the Shortcuts app, appear as
/// Spotlight suggestions, and become voice-invokable via the listed phrases. `\(.applicationName)`
/// resolves to the app's display name so phrases read naturally.
public struct SignalFlowShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: ["Open Dashboard in \(.applicationName)", "Show \(.applicationName) dashboard"],
            shortTitle: "Open Dashboard",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: OpenFleetStatusIntent(),
            phrases: ["Open Fleet Status in \(.applicationName)", "Show \(.applicationName) fleet"],
            shortTitle: "Fleet Status",
            systemImageName: "list.bullet.rectangle.fill"
        )
        AppShortcut(
            intent: OpenCriticalAlertsIntent(),
            phrases: ["Open Critical Alerts in \(.applicationName)", "Show \(.applicationName) alerts"],
            shortTitle: "Critical Alerts",
            systemImageName: "bell.fill"
        )
        AppShortcut(
            intent: ShowFleetSummaryIntent(),
            phrases: ["What's my \(.applicationName) fleet summary", "Get \(.applicationName) fleet summary"],
            shortTitle: "Fleet Summary",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
    }
}
