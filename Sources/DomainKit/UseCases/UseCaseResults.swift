/// A device plus its derived status and active-alert count, as shown in the fleet list.
public struct DeviceSummary: Hashable, Sendable {
    public let device: Device
    public let status: DeviceStatus
    public let activeAlertCount: Int

    public init(device: Device, status: DeviceStatus, activeAlertCount: Int) {
        self.device = device
        self.status = status
        self.activeAlertCount = activeAlertCount
    }
}

/// An asset and the summarized state of each of its devices.
public struct FleetOverview: Hashable, Sendable {
    public let asset: Asset
    public let devices: [DeviceSummary]

    public init(asset: Asset, devices: [DeviceSummary]) {
        self.asset = asset
        self.devices = devices
    }
}

/// The full detail of a single device: its derived status, latest readings, and active alerts.
public struct DeviceDetail: Hashable, Sendable {
    public let device: Device
    public let status: DeviceStatus
    public let latestReadings: [TelemetryReading]
    public let activeAlerts: [Alert]

    public init(
        device: Device,
        status: DeviceStatus,
        latestReadings: [TelemetryReading],
        activeAlerts: [Alert]
    ) {
        self.device = device
        self.status = status
        self.latestReadings = latestReadings
        self.activeAlerts = activeAlerts
    }
}
