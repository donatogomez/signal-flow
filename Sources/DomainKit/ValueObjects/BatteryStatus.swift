/// A device's battery state.
///
/// `percentage` is validated to `0...100`, so an impossible reading can never enter the domain.
public struct BatteryStatus: Hashable, Sendable {
    public let percentage: Double
    public let isCharging: Bool

    public init(percentage: Double, isCharging: Bool = false) throws {
        guard (0.0...100.0).contains(percentage) else {
            throw ValidationError.impossibleBatteryPercentage(percentage)
        }
        self.percentage = percentage
        self.isCharging = isCharging
    }

    public enum Level: String, Codable, Hashable, Sendable, CaseIterable {
        case critical
        case low
        case nominal
    }

    public var level: Level {
        switch percentage {
        case ..<10: .critical
        case ..<25: .low
        default: .nominal
        }
    }
}

extension BatteryStatus: Codable {
    private enum CodingKeys: String, CodingKey { case percentage, isCharging }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            percentage: container.decode(Double.self, forKey: .percentage),
            isCharging: container.decode(Bool.self, forKey: .isCharging)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(percentage, forKey: .percentage)
        try container.encode(isCharging, forKey: .isCharging)
    }
}
