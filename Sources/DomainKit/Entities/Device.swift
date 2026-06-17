/// A telemetry-emitting device attached to an ``Asset``.
///
/// Holds the device's identity, the metrics it can report, and its last-known operational state
/// (battery, connectivity, location). The derived ``DeviceStatus`` is intentionally *not* stored —
/// it is computed from connectivity and active alerts by ``DeviceHealthPolicy``.
public struct Device: Identifiable, Hashable, Sendable, Codable {
    public let id: DeviceID
    public let assetID: AssetID
    public let name: String
    public let metrics: [MetricDefinition]
    public let battery: BatteryStatus?
    public let connectivity: ConnectivityStatus
    public let lastKnownLocation: Location?

    public init(
        id: DeviceID = DeviceID(),
        assetID: AssetID,
        name: String,
        metrics: [MetricDefinition] = [],
        battery: BatteryStatus? = nil,
        connectivity: ConnectivityStatus = .offline,
        lastKnownLocation: Location? = nil
    ) throws {
        self.id = id
        self.assetID = assetID
        self.name = try DomainText.validatedName(name, context: "Device")
        self.metrics = metrics
        self.battery = battery
        self.connectivity = connectivity
        self.lastKnownLocation = lastKnownLocation
    }
}
