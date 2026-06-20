import Foundation
import DomainKit

/// A richer deep-link target that extends ``DeepLinkRoute`` with a **device-detail** destination.
///
/// Tab destinations reuse `DeepLinkRoute` verbatim (`signalflow://alerts`, …); a device adds
/// `signalflow://device/<uuid>`. Keeping both behind one parser means widgets, App Intents, and Live
/// Activities all speak the same scheme, and `RootView` has a single place to resolve a URL.
public enum DeepLink: Equatable, Sendable {
    case route(DeepLinkRoute)
    case device(DeviceID)

    public static let deviceHost = "device"

    public var url: URL {
        switch self {
        case .route(let route):
            route.url
        case .device(let id):
            URL(string: "\(DeepLinkRoute.scheme)://\(Self.deviceHost)/\(id.rawValue.uuidString)")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == DeepLinkRoute.scheme else { return nil }

        if url.host() == Self.deviceHost {
            let uuidString = url.pathComponents.first { $0 != "/" }
            guard let uuidString, let uuid = UUID(uuidString: uuidString) else { return nil }
            self = .device(DeviceID(uuid))
            return
        }

        guard let route = DeepLinkRoute(url: url) else { return nil }
        self = .route(route)
    }
}
