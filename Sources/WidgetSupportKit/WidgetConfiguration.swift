import AppIntents

/// A no-parameter configuration intent shared by both widgets.
///
/// Neither widget is user-configurable, but adopting `AppIntentConfiguration` lets the providers use
/// WidgetKit's **async** `snapshot`/`timeline` methods instead of completion handlers — which is the
/// clean fit for Swift 6 strict concurrency (no non-`Sendable` completion closure to smuggle into a
/// `Task`).
public struct SignalFlowWidgetConfiguration: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "SignalFlow"
    public static let description = IntentDescription("Shows persisted fleet status and alerts.")

    public init() {}

    public func perform() async throws -> some IntentResult { .result() }
}
