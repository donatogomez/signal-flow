/// The unit a telemetry value is expressed in.
///
/// Keeping units in the type system (rather than as bare `Double`s with units in comments) prevents
/// the classic "was that °C or °F?" defect class.
public enum MeasurementUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case celsius
    case fahrenheit
    case percent
    case partsPerMillion
    case decibelMilliwatts
    case volts
    case hectopascals
    case lux
    case count
    case unitless

    /// Short symbol for display and log messages (domain-level, not UI styling).
    public var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .percent: "%"
        case .partsPerMillion: "ppm"
        case .decibelMilliwatts: "dBm"
        case .volts: "V"
        case .hectopascals: "hPa"
        case .lux: "lx"
        case .count: ""
        case .unitless: ""
        }
    }
}
