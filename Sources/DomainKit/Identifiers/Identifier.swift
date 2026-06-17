import Foundation

/// A type-safe identifier.
///
/// `Scope` is a phantom type used only as a compile-time tag, so an `AssetID` can never be passed
/// where a `DeviceID` is expected even though both wrap a `UUID`. This eliminates a whole class of
/// "wrong id" bugs with zero runtime cost — the distinction lives entirely in the type system.
public struct Identifier<Scope>: Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

extension Identifier: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
}

extension Identifier: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

extension Identifier: CustomStringConvertible {
    public var description: String { rawValue.uuidString }
}

extension Identifier: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(UUID.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Domain identifier aliases

/// Each alias tags `Identifier` with the entity it belongs to. The entity type is used purely as a
/// marker — these are distinct, non-interchangeable types at compile time.
public typealias AssetID = Identifier<Asset>
public typealias DeviceID = Identifier<Device>
public typealias ReadingID = Identifier<TelemetryReading>
public typealias MetricID = Identifier<MetricDefinition>
public typealias AlertID = Identifier<Alert>
public typealias AlertRuleID = Identifier<AlertRule>
public typealias EventID = Identifier<DeviceEvent>
