import Foundation

/// The app's deep-link routing contract, shared by every "glance" surface — Home Screen widgets, App
/// Intents / Shortcuts, and Spotlight — and consumed by the app's `RootView`.
///
/// A surface hands the app a `signalflow://…` URL (or sets the in-app navigation model); the app maps
/// it back to a ``DeepLinkRoute`` and selects the matching tab. Keeping the scheme/host in one type
/// means the producers and the consumer can never drift apart on a string.
public enum DeepLinkRoute: String, Sendable, CaseIterable {
    case dashboard
    case fleet
    case alerts
    case insights

    public static let scheme = "signalflow"

    /// The deep-link URL for this destination (e.g. `signalflow://alerts`).
    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    /// Parses an incoming deep link back into a route, or `nil` if it isn't ours.
    public init?(url: URL) {
        guard url.scheme == Self.scheme, let route = DeepLinkRoute(rawValue: url.host() ?? "") else { return nil }
        self = route
    }
}
