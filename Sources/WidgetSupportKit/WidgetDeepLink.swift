import Foundation

/// The deep-link contract shared by the widgets and the app.
///
/// Tapping a widget hands the app a `signalflow://…` URL; `RootView` parses it back into a
/// ``WidgetRoute`` and selects the matching tab. Keeping the scheme/host in one type means the
/// producer (widget) and consumer (app) can never drift apart on a string.
public enum WidgetRoute: String, Sendable, CaseIterable {
    case dashboard
    case alerts

    public static let scheme = "signalflow"

    /// The URL a widget attaches via `.widgetURL(_:)` for this destination.
    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    /// Parses an incoming deep link back into a route, or `nil` if it isn't ours.
    public init?(url: URL) {
        guard url.scheme == Self.scheme, let route = WidgetRoute(rawValue: url.host() ?? "") else { return nil }
        self = route
    }
}
