import Foundation

/// A small retry policy for *transient* failures of *idempotent* requests only.
///
/// It never retries a `POST` or `PATCH`: when the response is lost, the server may already have
/// applied the request, and sending it again could apply it twice. It never retries cancellation,
/// decoding errors, or 4xx client errors (other than 408/429) either — retrying those is pointless or
/// harmful. Backoff is exponential from `baseDelay`, without jitter, and doesn't read `Retry-After`.
/// The delay is applied by an injectable sleeper in ``APIClient``, so tests run with no real waiting.
public struct RetryPolicy: Sendable {
    /// Total attempts, including the first. `1` means no retries.
    public var maxAttempts: Int
    public var baseDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(200)) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    /// Whether a request that failed with `error` is worth sending again.
    func isRetryable(_ error: NetworkError, method: HTTPMethod) -> Bool {
        switch method {
        case .get, .put, .delete: break
        case .post, .patch: return false
        }
        switch error {
        case .transport:
            return true
        case .unacceptableStatusCode(let code):
            return code == 408 || code == 429 || (500...599).contains(code)
        case .invalidURL, .nonHTTPResponse, .decoding, .cancelled, .unknown:
            return false
        }
    }

    /// Exponential backoff for a 1-based attempt number.
    func delay(forAttempt attempt: Int) -> Duration {
        baseDelay * (1 << max(0, attempt - 1))
    }
}
