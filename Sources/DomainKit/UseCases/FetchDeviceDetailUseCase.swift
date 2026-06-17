/// Assembles a single device's detail, fetching its latest readings and active alerts concurrently
/// and deriving its status.
public struct FetchDeviceDetailUseCase: Sendable {
    private let devices: any DeviceRepository
    private let telemetry: any TelemetryRepository
    private let alerts: any AlertRepository

    public init(
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository
    ) {
        self.devices = devices
        self.telemetry = telemetry
        self.alerts = alerts
    }

    public func callAsFunction(deviceID: DeviceID) async throws -> DeviceDetail {
        let device = try await devices.device(deviceID)

        // The two reads are independent, so run them concurrently with structured `async let`.
        async let latest = telemetry.latestReadings(forDevice: deviceID)
        async let active = alerts.activeAlerts(forDevice: deviceID)
        let readings = try await latest
        let activeAlerts = try await active

        let status = DeviceHealthPolicy.status(
            connectivity: device.connectivity,
            activeAlerts: activeAlerts
        )
        return DeviceDetail(
            device: device,
            status: status,
            latestReadings: readings,
            activeAlerts: activeAlerts
        )
    }
}
