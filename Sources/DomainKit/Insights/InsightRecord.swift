import Foundation

/// A persisted insight: a ``DeviceInsight`` tagged with the device, metric, and when it was generated.
///
/// A pure domain value type — the persistence layer maps it to and from its storage models, so the
/// Domain stays unaware of how (or whether) insights are stored.
public struct InsightRecord: Sendable, Hashable, Identifiable {
    public let id: ReadingID   // a fresh identifier per generated insight
    public let deviceID: DeviceID
    public let metric: MetricKind
    public let insight: DeviceInsight
    public let createdAt: Date

    public init(
        id: ReadingID = ReadingID(),
        deviceID: DeviceID,
        metric: MetricKind,
        insight: DeviceInsight,
        createdAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.metric = metric
        self.insight = insight
        self.createdAt = createdAt
    }
}
