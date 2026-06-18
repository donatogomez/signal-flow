import Foundation
import Testing
import DomainKit
import NetworkingKit

@Suite("Remote gateway")
struct RemoteGatewayTests {

    private func gateway(_ json: Data) -> (SignalFlowRemoteGateway, StubHTTPClient) {
        let stub = StubHTTPClient(json: json)
        return (SignalFlowRemoteGateway(baseURL: NetFixtures.baseURL, transport: stub), stub)
    }

    @Test("Fetches assets and hits the right path")
    func assets() async throws {
        let (gateway, stub) = gateway(NetFixtures.assetsJSON)
        let assets = try await gateway.assets()
        #expect(assets.count == 1)
        #expect(assets.first?.kind == .greenhouse)
        let request = await stub.lastRequest
        #expect(request?.url?.path == "/v1/assets")
        #expect(request?.httpMethod == "GET")
    }

    @Test("Fetches a device's telemetry with metric/from/to query items")
    func telemetry() async throws {
        let (gateway, stub) = gateway(NetFixtures.telemetryJSON)
        let deviceID = DeviceID()
        let range = try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1000))
        let readings = try await gateway.telemetry(forDevice: deviceID, metric: .temperature, in: range)
        #expect(readings.count == 1)
        let query = await stub.lastRequest?.url?.query ?? ""
        #expect(query.contains("metric=temperature"))
        #expect(query.contains("from="))
        #expect(query.contains("to="))
    }

    @Test("Fetches alerts and events")
    func alertsAndEvents() async throws {
        let (alertGateway, _) = gateway(NetFixtures.alertsJSON)
        #expect(try await alertGateway.alerts(forDevice: DeviceID()).count == 1)

        let (eventGateway, _) = gateway(NetFixtures.eventsJSON)
        let events = try await eventGateway.events(forDevice: DeviceID(), limit: 10)
        #expect(events.first?.kind == .doorOpened)
    }

    @Test("Acknowledge sends a POST to the acknowledge path and needs no body decode")
    func acknowledge() async throws {
        let stub = StubHTTPClient([.status(204)])
        let gateway = SignalFlowRemoteGateway(baseURL: NetFixtures.baseURL, transport: stub)
        try await gateway.acknowledgeAlert(AlertID(), at: Date(timeIntervalSince1970: 1))
        let request = await stub.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path.hasSuffix("/acknowledge") == true)
    }

    @Test("Server errors surface as NetworkError")
    func serverError() async {
        let stub = StubHTTPClient([.status(503)])
        let gateway = SignalFlowRemoteGateway(baseURL: NetFixtures.baseURL, transport: stub, retry: .none)
        await #expect(throws: NetworkError.unacceptableStatusCode(503)) { _ = try await gateway.assets() }
    }
}
