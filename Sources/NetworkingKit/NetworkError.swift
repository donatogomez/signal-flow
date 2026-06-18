import Foundation

/// Structured networking errors — the single error type that surfaces from this layer.
///
/// `Equatable` so tests can assert precisely; transport failures carry the `URLError` code so the
/// retry policy can reason about them without holding a non-`Sendable` `Error`.
public enum NetworkError: Error, Sendable, Equatable {
    /// The endpoint produced an invalid URL.
    case invalidURL
    /// The response was not an `HTTPURLResponse`.
    case nonHTTPResponse
    /// A non-2xx status code.
    case unacceptableStatusCode(Int)
    /// The body could not be decoded into the expected type.
    case decoding(String)
    /// A transport-level failure (timeout, connection lost, DNS, …).
    case transport(code: Int)
    /// The request was cancelled.
    case cancelled
    /// Anything else.
    case unknown(String)

    /// Normalizes any thrown error into a `NetworkError`.
    static func map(_ error: Error) -> NetworkError {
        switch error {
        case let network as NetworkError:
            return network
        case is CancellationError:
            return .cancelled
        case let urlError as URLError:
            return urlError.code == .cancelled ? .cancelled : .transport(code: urlError.code.rawValue)
        default:
            return .unknown(String(describing: error))
        }
    }
}
