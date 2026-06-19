import Observation
import SnapshotKit

/// The bridge from App Intents into SwiftUI navigation.
///
/// An `AppIntent` can't push a tab directly, so the "Open …" intents publish a ``DeepLinkRoute`` here
/// and the app's `RootView` observes it and selects the matching tab. A single shared instance is the
/// rendezvous point: intents run in the app's process (even when launched in the background from
/// Shortcuts), so the same `@MainActor` object they write is the one the UI reads.
@MainActor
@Observable
public final class AppNavigationModel {
    public static let shared = AppNavigationModel()

    /// A route an intent has asked the app to show; `RootView` consumes and clears it.
    public var pendingRoute: DeepLinkRoute?

    public init() {}

    /// Requests navigation to `route` on the next UI update.
    public func request(_ route: DeepLinkRoute) { pendingRoute = route }
}
