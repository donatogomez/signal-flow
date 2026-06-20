import SwiftUI
import DomainKit

/// The product's visual + linguistic vocabulary for domain concepts. Keeping these mappings in one
/// place (rather than scattered in feature views) means status, severity, and asset semantics look —
/// and *read* — identical everywhere, and a feature never has to invent a color or a translation for
/// "critical".
///
/// **Localization lives here, in the presentation layer — never in `DomainKit`.** Domain enums stay
/// language-neutral; these computed labels resolve against `DesignSystemKit`'s string catalog
/// (`Bundle.module`) via `String(localized:)`, so they're returned already-translated for the user's
/// language with no change required at the hundreds of call sites that render them.
/// Resolves a key against DesignSystemKit's string catalog. `locale` is injectable so tests can assert
/// a specific language deterministically (instead of depending on the CI machine's region).
enum DSKLocalization {
    static func string(_ key: String.LocalizationValue, locale: Locale = .current) -> String {
        var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = locale
        return String(localized: resource)
    }

    /// The on-disk string catalog shipped in DesignSystemKit's resource bundle. Exposed so tests can
    /// validate the Spanish translations from the catalog itself — Xcode compiles `.xcstrings` into
    /// `.lproj` at build time, but the SwiftPM CLI only copies the raw catalog, so asserting *content*
    /// is the deterministic, toolchain-independent way to test translations.
    static var catalogURL: URL? {
        Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
    }
}

private func dsk(_ key: String.LocalizationValue) -> String {
    DSKLocalization.string(key)
}

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
        case .nominal: dsk("Nominal")
        case .warning: dsk("Warning")
        case .critical: dsk("Critical")
        case .offline: dsk("Offline")
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
        case .info: dsk("Info")
        case .warning: dsk("Warning")
        case .critical: dsk("Critical")
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
        case .online: dsk("Online")
        case .degraded: dsk("Degraded")
        case .offline: dsk("Offline")
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
    /// Localized, user-facing asset-type name. (The neutral `displayName` stays in DomainKit for keys,
    /// sorting, and identity.)
    var localizedName: String {
        switch self {
        case .greenhouse: dsk("Greenhouse")
        case .refrigeratedTruck: dsk("Refrigerated truck")
        case .coldChainContainer: dsk("Cold-chain container")
        case .warehouse: dsk("Warehouse")
        case .industrialEquipment: dsk("Industrial equipment")
        case .environmentalStation: dsk("Environmental station")
        }
    }

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
        case .nominal: dsk("Nominal")
        case .watch: dsk("Watch")
        case .concern: dsk("Concern")
        }
    }
}

public extension InsightSource {
    var label: String {
        switch self {
        case .foundationModel: dsk("On-device AI")
        case .deterministic: dsk("Deterministic")
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
        case .doorOpened: dsk("Door opened")
        case .doorClosed: dsk("Door closed")
        case .connected: dsk("Reconnected")
        case .disconnected: dsk("Connection lost")
        case .powerLost: dsk("Power lost")
        case .powerRestored: dsk("Power restored")
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
    /// Localized, user-facing metric name for rows and chart headers. (The neutral `displayName` stays
    /// in DomainKit and is used for sorting and SwiftUI identity, which must not shift by language.)
    var localizedName: String {
        switch self {
        case .temperature: dsk("Temperature")
        case .humidity: dsk("Humidity")
        case .carbonDioxide: dsk("Carbon dioxide")
        case .batteryLevel: dsk("Battery level")
        case .signalStrength: dsk("Signal strength")
        case .custom(let key): key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

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
