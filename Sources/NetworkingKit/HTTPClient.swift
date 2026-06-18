import Foundation

/// The transport seam: performs a `URLRequest` and returns the raw data plus the HTTP response.
///
/// It does **not** validate status codes or decode — those are higher-level concerns in ``APIClient``.
/// Keeping the transport this thin is what lets a deterministic ``StubHTTPClient`` stand in for
/// `URLSession` in tests with no real backend.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The production transport, backed by `URLSession` and its cancellation-aware `async` API.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.nonHTTPResponse }
        return (data, http)
    }
}
