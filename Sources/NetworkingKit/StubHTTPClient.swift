import Foundation

/// A deterministic, in-process `HTTPClient` for tests and for running with **no real backend**.
///
/// It returns a scripted sequence of outcomes (repeating the last once exhausted) and records every
/// request it received, so tests can validate request construction, decoding, status handling,
/// transport errors, and retry counts — all without a network. It's an `actor`, so concurrent use is
/// safe with no `@unchecked Sendable`.
public actor StubHTTPClient: HTTPClient {
    public enum Outcome: Sendable {
        case success(Data, status: Int)
        case transportError(URLError)

        public static func ok(_ data: Data) -> Outcome { .success(data, status: 200) }
        public static func status(_ code: Int, _ data: Data = Data()) -> Outcome { .success(data, status: code) }
    }

    private var outcomes: [Outcome]
    public private(set) var requestCount = 0
    public private(set) var capturedRequests: [URLRequest] = []

    public init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes.isEmpty ? [.transportError(URLError(.badServerResponse))] : outcomes
    }

    public init(json: Data, status: Int = 200) {
        self.outcomes = [.success(json, status: status)]
    }

    public var lastRequest: URLRequest? { capturedRequests.last }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        capturedRequests.append(request)

        // Consume outcomes in order; once a single outcome remains, keep returning it.
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : (outcomes.first ?? .transportError(URLError(.badServerResponse)))

        switch outcome {
        case .success(let data, let status):
            let url = request.url ?? URL(string: "https://stub.invalid")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (data, response)
        case .transportError(let error):
            throw error
        }
    }
}
