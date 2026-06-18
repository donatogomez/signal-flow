import Foundation
import DomainKit

/// The remote API abstraction — fetches the fleet and its telemetry as **`DomainKit` entities**.
///
/// This is the seam DataKit orchestrates against: it returns domain types, so DataKit (and features)
/// never see DTOs, endpoints, or HTTP. Reads cover assets, devices, telemetry (latest + history),
/// events, and alerts; acknowledgement is the one write a client makes.
public protocol RemoteGateway: Sendable {
    func assets() async throws -> [Asset]
    func devices(inAsset assetID: AssetID) async throws -> [Device]
    func device(_ id: DeviceID) async throws -> Device
    func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading]
    func telemetry(forDevice deviceID: DeviceID, metric: MetricKind, in range: TimeRange) async throws -> [TelemetryReading]
    func events(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent]
    func alerts(forDevice deviceID: DeviceID) async throws -> [Alert]
    func acknowledgeAlert(_ id: AlertID, at date: Date) async throws
}

/// The HTTP implementation of ``RemoteGateway``. It defines the endpoints, sends them through the
/// `APIClient`, and maps the DTOs to domain entities. Production-shaped, but driven entirely by an
/// injected transport — so a `StubHTTPClient` exercises the whole path in tests.
public struct SignalFlowRemoteGateway: RemoteGateway {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Convenience: build a gateway from a base URL and transport.
    public init(baseURL: URL, transport: any HTTPClient, retry: RetryPolicy = .default) {
        self.client = APIClient(baseURL: baseURL, transport: transport, retry: retry)
    }

    public func assets() async throws -> [Asset] {
        try await client.send(AssetsEndpoint()).map(DTOMapping.asset)
    }

    public func devices(inAsset assetID: AssetID) async throws -> [Device] {
        try await client.send(DevicesEndpoint(assetID: assetID.rawValue.uuidString)).map(DTOMapping.device)
    }

    public func device(_ id: DeviceID) async throws -> Device {
        try DTOMapping.device(try await client.send(DeviceEndpoint(deviceID: id.rawValue.uuidString)))
    }

    public func latestReadings(forDevice deviceID: DeviceID) async throws -> [TelemetryReading] {
        try await client.send(LatestTelemetryEndpoint(deviceID: deviceID.rawValue.uuidString)).map(DTOMapping.reading)
    }

    public func telemetry(forDevice deviceID: DeviceID, metric: MetricKind, in range: TimeRange) async throws -> [TelemetryReading] {
        let endpoint = TelemetryEndpoint(
            deviceID: deviceID.rawValue.uuidString,
            metricKey: DTOMapping.metricKey(metric),
            from: range.start, to: range.end
        )
        return try await client.send(endpoint).map(DTOMapping.reading)
    }

    public func events(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent] {
        try await client.send(EventsEndpoint(deviceID: deviceID.rawValue.uuidString, limit: limit)).map(DTOMapping.event)
    }

    public func alerts(forDevice deviceID: DeviceID) async throws -> [Alert] {
        try await client.send(AlertsEndpoint(deviceID: deviceID.rawValue.uuidString)).map(DTOMapping.alert)
    }

    public func acknowledgeAlert(_ id: AlertID, at date: Date) async throws {
        try await client.sendIgnoringResponse(AcknowledgeAlertEndpoint(alertID: id.rawValue.uuidString, at: date))
    }
}

// MARK: - Endpoints

private struct AssetsEndpoint: Endpoint {
    typealias Response = [AssetDTO]
    let path = "assets"
}

private struct DevicesEndpoint: Endpoint {
    typealias Response = [DeviceDTO]
    let assetID: String
    var path: String { "assets/\(assetID)/devices" }
}

private struct DeviceEndpoint: Endpoint {
    typealias Response = DeviceDTO
    let deviceID: String
    var path: String { "devices/\(deviceID)" }
}

private struct LatestTelemetryEndpoint: Endpoint {
    typealias Response = [TelemetryReadingDTO]
    let deviceID: String
    var path: String { "devices/\(deviceID)/telemetry/latest" }
}

private struct TelemetryEndpoint: Endpoint {
    typealias Response = [TelemetryReadingDTO]
    let deviceID: String
    let metricKey: String
    let from: Date
    let to: Date
    var path: String { "devices/\(deviceID)/telemetry" }
    var queryItems: [URLQueryItem] {
        let formatter = ISO8601DateFormatter()
        return [
            URLQueryItem(name: "metric", value: metricKey),
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to)),
        ]
    }
}

private struct EventsEndpoint: Endpoint {
    typealias Response = [DeviceEventDTO]
    let deviceID: String
    let limit: Int
    var path: String { "devices/\(deviceID)/events" }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "limit", value: String(limit))] }
}

private struct AlertsEndpoint: Endpoint {
    typealias Response = [AlertDTO]
    let deviceID: String
    var path: String { "devices/\(deviceID)/alerts" }
}

private struct AcknowledgeAlertEndpoint: Endpoint {
    typealias Response = EmptyResponse
    let alertID: String
    let at: Date
    var path: String { "alerts/\(alertID)/acknowledge" }
    var method: HTTPMethod { .post }
    var body: Data? {
        let formatter = ISO8601DateFormatter()
        return try? JSONEncoder().encode(["acknowledgedAt": formatter.string(from: at)])
    }
}
