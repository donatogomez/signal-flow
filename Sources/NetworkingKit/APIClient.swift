import Foundation

/// The HTTP request/response engine: builds requests from endpoints, performs them through an
/// `HTTPClient` with retry, validates the status code, decodes the body, and maps every failure into
/// a ``NetworkError``.
///
/// `Sendable` and dependency-injected throughout — the transport, retry policy, and the sleeper used
/// for backoff are all supplied, so the same client drives `URLSession` in production and a
/// deterministic stub in tests.
public struct APIClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPClient
    private let retry: RetryPolicy
    private let defaultHeaders: [String: String]
    private let sleeper: @Sendable (Duration) async throws -> Void

    public init(
        baseURL: URL,
        transport: any HTTPClient,
        retry: RetryPolicy = .default,
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.retry = retry
        self.defaultHeaders = defaultHeaders
        self.sleeper = sleeper
    }

    /// Sends an endpoint and decodes its `Response`.
    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let request = try RequestBuilder.makeRequest(endpoint, baseURL: baseURL, defaultHeaders: defaultHeaders)
        let data = try await performWithRetry(request)
        return try decode(E.Response.self, from: data)
    }

    /// Sends an endpoint and ignores the response body (writes / `204 No Content`).
    public func sendIgnoringResponse<E: Endpoint>(_ endpoint: E) async throws {
        let request = try RequestBuilder.makeRequest(endpoint, baseURL: baseURL, defaultHeaders: defaultHeaders)
        _ = try await performWithRetry(request)
    }

    // MARK: - Internals

    private func performWithRetry(_ request: URLRequest) async throws -> Data {
        var attempt = 1
        while true {
            do {
                try Task.checkCancellation()
                return try await fetchValidated(request)
            } catch {
                let mapped = NetworkError.map(error)
                guard mapped != .cancelled, attempt < retry.maxAttempts, retry.isRetryable(mapped) else {
                    throw mapped
                }
                try await sleeper(retry.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    private func fetchValidated(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if type == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! T }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decoding(String(describing: error))
        }
    }
}
