import Foundation
import DomainKit

/// A current-telemetry row (one per metric the device reports).
public struct ReadingRow: Identifiable, Sendable, Hashable {
    public let id: String          // metric key, stable per metric
    public let metric: MetricKind
    public let valueText: String
    public let recordedAt: Date
}

/// One point on a trend chart.
public struct TrendPoint: Identifiable, Sendable, Hashable {
    public let id: ReadingID
    public let date: Date
    public let value: Double
}

/// A chart-ready series for one metric.
public struct TrendSeries: Sendable, Hashable {
    public let metric: MetricKind
    public let unitSymbol: String
    public let points: [TrendPoint]

    public var isEmpty: Bool { points.count < 2 }
}

/// An active-alert row for the device.
public struct AlertRow: Identifiable, Sendable, Hashable {
    public let id: AlertID
    public let message: String
    public let severity: AlertSeverity
    public let raisedAt: Date
    public let isAcknowledged: Bool
}

/// A recent-event row for the device.
public struct DeviceEventRow: Identifiable, Sendable, Hashable {
    public let id: EventID
    public let kind: DeviceEvent.Kind
    public let occurredAt: Date
}
