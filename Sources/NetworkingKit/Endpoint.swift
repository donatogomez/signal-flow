import Foundation

/// A strongly-typed endpoint: its path, method, query, headers, body, and the `Response` it decodes to.
///
/// The phantom `Response` type ties an endpoint to exactly what it returns, so `APIClient.send`
/// infers the decoded type at the call site — no stringly-typed plumbing.
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
}

public extension Endpoint {
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var body: Data? { nil }
}

/// An empty decodable for endpoints with no meaningful response body (e.g. a `204 No Content` write).
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

/// Builds a `URLRequest` from an endpoint and a base URL.
enum RequestBuilder {
    static func makeRequest(
        _ endpoint: some Endpoint,
        baseURL: URL,
        defaultHeaders: [String: String]
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        if !endpoint.queryItems.isEmpty { components.queryItems = endpoint.queryItems }
        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        // Default headers first, then endpoint headers (which may override).
        for (field, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: field) }
        for (field, value) in endpoint.headers { request.setValue(value, forHTTPHeaderField: field) }
        if endpoint.body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
