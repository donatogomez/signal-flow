import Foundation

/// A half-open-friendly, validated interval of time used for history queries.
///
/// Construction guarantees `start <= end`, so every `TimeRange` in the system is well-formed and
/// callers never have to defend against inverted ranges.
public struct TimeRange: Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) throws {
        guard start <= end else { throw ValidationError.invalidTimeRange(start: start, end: end) }
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

extension TimeRange: Codable {
    private enum CodingKeys: String, CodingKey { case start, end }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            start: container.decode(Date.self, forKey: .start),
            end: container.decode(Date.self, forKey: .end)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}
