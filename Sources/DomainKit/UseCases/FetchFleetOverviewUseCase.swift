/// Builds the fleet overview: every asset, each with its devices' derived status and active-alert
/// counts.
public struct FetchFleetOverviewUseCase: Sendable {
    private let assets: any AssetRepository
    private let devices: any DeviceRepository
    private let alerts: any AlertRepository

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository
    ) {
        self.assets = assets
        self.devices = devices
        self.alerts = alerts
    }

    public func callAsFunction() async throws -> [FleetOverview] {
        var overviews: [FleetOverview] = []
        for asset in try await assets.allAssets() {
            var summaries: [DeviceSummary] = []
            for device in try await devices.devices(inAsset: asset.id) {
                let active = try await alerts.activeAlerts(forDevice: device.id)
                let status = DeviceHealthPolicy.status(
                    connectivity: device.connectivity,
                    activeAlerts: active
                )
                summaries.append(
                    DeviceSummary(device: device, status: status, activeAlertCount: active.count)
                )
            }
            overviews.append(FleetOverview(asset: asset, devices: summaries))
        }
        return overviews
    }
}
