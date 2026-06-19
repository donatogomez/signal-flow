import SnapshotKit

/// Wires the App Intents dependency seam at launch.
///
/// All intents run **in the app's process** (the system launches the app — foreground or background —
/// to execute them, since there's no separate App Intents extension target). So setting the
/// `FleetSummaryProviding` once in the app's `init` is enough for every invocation, including
/// background Shortcuts/Siri runs.
public enum AppIntentsBootstrap {
    @MainActor
    public static func register(
        fleetSummaryProvider: any FleetSummaryProviding = PersistedFleetSummaryProvider()
    ) {
        AppIntentsEnvironment.fleetSummaryProvider = fleetSummaryProvider
    }
}
