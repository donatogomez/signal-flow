import AppIntents
import SnapshotKit

/// Returns a spoken/textual fleet summary **without opening the app** — answerable inline in Shortcuts
/// and by Siri. It reads the persisted snapshot through an injected ``FleetSummaryProviding`` (resolved
/// via App Intents' `@Dependency`), so it never touches the live data engine.
public struct ShowFleetSummaryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Fleet Summary"
    public static let description = IntentDescription(
        "Reads the latest saved fleet status — how many devices are online, in warning, or critical."
    )
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let summary = try await AppIntentsEnvironment.fleetSummaryProvider.currentSummary()
        let text = summary.spokenSummary
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}
