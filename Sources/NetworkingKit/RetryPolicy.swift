import Foundation

/// A small retry policy for *transient* failures only.
///
/// It never retries cancellation, decoding errors, or 4xx client errors (other than 408/429) —
/// retrying those is pointless or harmful. Backoff is exponential from `baseDelay`. The delay is
/// applied by an injectable sleeper in ``APIClient``, so tests run with no real waiting.
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

    /// Whether an error is worth retrying.
    func isRetryable(_ error: NetworkError) -> Bool {
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
