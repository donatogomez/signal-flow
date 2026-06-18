import SwiftUI
import DomainKit

/// The product's visual vocabulary for domain concepts. Keeping these mappings in one place (rather
/// than scattered in feature views) means status, severity, and asset semantics look identical
/// everywhere, and a feature never has to invent a color for "critical".

public extension DeviceStatus {
    var tint: Color {
        switch self {
        case .nominal: .green
        case .warning: .orange
        case .critical: .red
        case .offline: .secondary
        }
    }

    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .warning: "Warning"
        case .critical: "Critical"
        case .offline: "Offline"
        }
    }

    var symbol: String {
        switch self {
        case .nominal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .offline: "wifi.slash"
        }
    }
}

public extension AlertSeverity {
    var tint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    var label: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

public extension ConnectivityStatus.State {
    var tint: Color {
        switch self {
        case .online: .green
        case .degraded: .orange
        case .offline: .secondary
        }
    }

    var label: String {
        switch self {
        case .online: "Online"
        case .degraded: "Degraded"
        case .offline: "Offline"
        }
    }

    var symbol: String {
        switch self {
        case .online: "wifi"
        case .degraded: "wifi.exclamationmark"
        case .offline: "wifi.slash"
        }
    }
}

public extension BatteryStatus {
    var tint: Color {
        switch level {
        case .critical: .red
        case .low: .orange
        case .nominal: .green
        }
    }

    var symbol: String {
        switch level {
        case .critical: "battery.0percent"
        case .low: "battery.25percent"
        case .nominal: "battery.100percent"
        }
    }
}

public extension AssetKind {
    var symbol: String {
        switch self {
        case .greenhouse: "leaf.fill"
        case .refrigeratedTruck: "truck.box.fill"
        case .coldChainContainer: "shippingbox.fill"
        case .warehouse: "building.2.fill"
        case .industrialEquipment: "gearshape.2.fill"
        case .environmentalStation: "sensor.fill"
        }
    }
}

public extension InsightSeverity {
    /// Advisory tint for an insight's noteworthiness — distinct from safety-status colors.
    var tint: Color {
        switch self {
        case .nominal: .green
        case .watch: .orange
        case .concern: .red
        }
    }

    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .watch: "Watch"
        case .concern: "Concern"
        }
    }
}

public extension InsightSource {
    var label: String {
        switch self {
        case .foundationModel: "On-device AI"
        case .deterministic: "Deterministic"
        }
    }

    var symbol: String {
        switch self {
        case .foundationModel: "sparkles"
        case .deterministic: "function"
        }
    }
}

public extension DeviceEvent.Kind {
    var title: String {
        switch self {
        case .doorOpened: "Door opened"
        case .doorClosed: "Door closed"
        case .connected: "Reconnected"
        case .disconnected: "Connection lost"
        case .powerLost: "Power lost"
        case .powerRestored: "Power restored"
        case .custom(let key): key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch self {
        case .doorOpened, .doorClosed: "door.left.hand.open"
        case .connected: "wifi"
        case .disconnected: "wifi.slash"
        case .powerLost: "bolt.slash.fill"
        case .powerRestored: "bolt.fill"
        case .custom: "exclamationmark.bubble.fill"
        }
    }

    var tint: Color {
        switch self {
        case .doorOpened, .doorClosed: .blue
        case .connected, .powerRestored: .green
        case .disconnected, .powerLost: .red
        case .custom: .orange
        }
    }
}

public extension MetricKind {
    /// SF Symbol for a metric, used in detail rows and chart headers.
    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .humidity: "humidity.fill"
        case .carbonDioxide: "carbon.dioxide.cloud.fill"
        case .batteryLevel: "battery.100percent"
        case .signalStrength: "antenna.radiowaves.left.and.right"
        case .custom: "dot.radiowaves.up.forward"
        }
    }
}
