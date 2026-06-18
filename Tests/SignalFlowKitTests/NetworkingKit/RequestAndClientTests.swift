import Foundation
import Testing
@testable import NetworkingKit

private struct Echo: Codable, Sendable, Equatable { let message: String }
private struct EchoEndpoint: Endpoint { typealias Response = Echo; let path = "echo" }

@Suite("Request construction")
struct RequestBuilderTests {

    private struct WriteEndpoint: Endpoint {
        typealias Response = EmptyResponse
        let path = "devices/42/telemetry"
        var method: HTTPMethod { .post }
        var queryItems: [URLQueryItem] { [URLQueryItem(name: "metric", value: "temperature")] }
        var headers: [String: String] { ["X-Trace": "abc"] }
        var body: Data? { Data("{}".utf8) }
    }

    @Test("Builds URL, method, query, headers, and content-type from an endpoint")
    func buildsRequest() throws {
        let request = try RequestBuilder.makeRequest(
            WriteEndpoint(),
            baseURL: URL(string: "https://api.signalflow.test/v1")!,
            defaultHeaders: ["Accept": "application/json"]
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.signalflow.test/v1/devices/42/telemetry?metric=temperature")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Trace") == "abc")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json") // body present
        #expect(request.httpBody == Data("{}".utf8))
    }
}

@Suite("API client")
struct APIClientTests {

    private func client(_ outcomes: [StubHTTPClient.Outcome], retry: RetryPolicy = .none) -> (APIClient, StubHTTPClient) {
        let stub = StubHTTPClient(outcomes)
        // No real backoff: the injected sleeper does nothing.
        let api = APIClient(baseURL: URL(string: "https://api.test")!, transport: stub, retry: retry, sleeper: { _ in })
        return (api, stub)
    }

    @Test("Decodes a successful response")
    func decodesSuccess() async throws {
        let (api, _) = client([.ok(Data(#"{"message":"hi"}"#.utf8))])
        #expect(try await api.send(EchoEndpoint()) == Echo(message: "hi"))
    }

    @Test("A non-2xx status maps to unacceptableStatusCode")
    func invalidStatus() async {
        let (api, _) = client([.status(500)])
        await #expect(throws: NetworkError.unacceptableStatusCode(500)) { _ = try await api.send(EchoEndpoint()) }
    }

    @Test("A transport error maps to .transport")
    func transportError() async {
        let (api, _) = client([.transportError(URLError(.timedOut))])
        await #expect(throws: NetworkError.transport(code: URLError.Code.timedOut.rawValue)) {
            _ = try await api.send(EchoEndpoint())
        }
    }

    @Test("A decoding failure maps to .decoding")
    func decodingFailure() async {
        let (api, _) = client([.ok(Data(#"{"nope":1}"#.utf8))])
        await #expect(throws: NetworkError.self) { _ = try await api.send(EchoEndpoint()) }
    }

    @Test("Transient failures are retried, then succeed")
    func retriesThenSucceeds() async throws {
        let (api, stub) = client(
            [.transportError(URLError(.networkConnectionLost)),
             .transportError(URLError(.networkConnectionLost)),
             .ok(Data(#"{"message":"ok"}"#.utf8))],
            retry: RetryPolicy(maxAttempts: 3, baseDelay: .zero)
        )
        let echo = try await api.send(EchoEndpoint())
        let attempts = await stub.requestCount
        #expect(echo.message == "ok")
        #expect(attempts == 3)
    }

    @Test("Retry exhausts attempts and throws")
    func retryExhausts() async {
        let (api, stub) = client([.transportError(URLError(.timedOut))], retry: RetryPolicy(maxAttempts: 2, baseDelay: .zero))
        await #expect(throws: NetworkError.self) { _ = try await api.send(EchoEndpoint()) }
        let attempts = await stub.requestCount
        #expect(attempts == 2)
    }

    @Test("Decoding errors and 4xx client errors are not retried")
    func nonRetryable() async {
        let retry = RetryPolicy(maxAttempts: 3, baseDelay: .zero)

        let (decodeApi, decodeStub) = client([.ok(Data(#"{"nope":1}"#.utf8))], retry: retry)
        await #expect(throws: NetworkError.self) { _ = try await decodeApi.send(EchoEndpoint()) }
        #expect(await decodeStub.requestCount == 1)

        let (clientApi, clientStub) = client([.status(404)], retry: retry)
        await #expect(throws: NetworkError.unacceptableStatusCode(404)) { _ = try await clientApi.send(EchoEndpoint()) }
        #expect(await clientStub.requestCount == 1)
    }

    @Test("Cancellation propagates as .cancelled")
    func cancellation() async {
        struct HangingClient: HTTPClient {
            func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                try await Task.sleep(for: .seconds(60))
                throw NetworkError.unknown("unreachable")
            }
        }
        let api = APIClient(baseURL: URL(string: "https://api.test")!, transport: HangingClient(), retry: .none, sleeper: { _ in })
        let task = Task { try await api.send(EchoEndpoint()) }
        task.cancel()
        await #expect(throws: NetworkError.cancelled) { _ = try await task.value }
    }
}
