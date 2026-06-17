import Foundation
import DomainKit

/// Test data builders. Uses only `DomainKit`'s public API — if these compile, the public surface is
/// sufficient to model the domain from the outside.
enum Fixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func temperatureReading(
        _ celsius: Double,
        deviceID: DeviceID,
        at offset: TimeInterval = 0
    ) throws -> TelemetryReading {
        TelemetryReading(
            deviceID: deviceID,
            metric: .temperature,
            value: try MeasuredValue(magnitude: celsius, unit: .celsius),
            recordedAt: referenceDate.addingTimeInterval(offset)
        )
    }

    static func temperatureRule(
        max: Double,
        severity: AlertSeverity = .critical,
        enabled: Bool = true
    ) throws -> AlertRule {
        try AlertRule(
            name: "Max temperature",
            metric: .temperature,
            threshold: try Threshold(upperBound: max),
            severity: severity,
            isEnabled: enabled
        )
    }

    static func device(
        id: DeviceID = DeviceID(),
        connectivity: ConnectivityStatus = ConnectivityStatus(state: .online)
    ) throws -> Device {
        try Device(assetID: AssetID(), name: "Reefer 12", connectivity: connectivity).withID(id)
    }
}

private extension Device {
    /// Rebuilds the device with a specific id (Device's id is `let`, so we reconstruct).
    func withID(_ id: DeviceID) throws -> Device {
        try Device(
            id: id,
            assetID: assetID,
            name: name,
            metrics: metrics,
            battery: battery,
            connectivity: connectivity,
            lastKnownLocation: lastKnownLocation
        )
    }
}
