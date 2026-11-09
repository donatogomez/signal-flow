/// The complete set of grounded facts an insight is generated from.
///
/// Assembled by ``GenerateDeviceInsightUseCase`` from repositories and ``InsightStatistics``, then
/// passed to an ``InsightsProviding`` implementation. Everything here is a fact computed in Swift —
/// device identity, the metric statistics, and *counts* of active alerts and recent events. Crucially,
/// alert evaluation has already happened deterministically elsewhere; the model only ever sees the
/// resulting count, never the thresholds.
public struct InsightContext: Sendable, Hashable {
    public let deviceID: DeviceID
    public let deviceName: String
    public let assetKind: AssetKind
    public let statistics: InsightStatistics
    public let activeAlertCount: Int
    public let recentEventCount: Int
    public let range: TimeRange

    public init(
        deviceID: DeviceID,
        deviceName: String,
        assetKind: AssetKind,
        statistics: InsightStatistics,
        activeAlertCount: Int,
        recentEventCount: Int,
        range: TimeRange
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.assetKind = assetKind
        self.statistics = statistics
        self.activeAlertCount = activeAlertCount
        self.recentEventCount = recentEventCount
        self.range = range
    }

    public var metric: MetricKind { statistics.metric }

    /// The insight's advisory severity, decided **from these facts in Swift** — never by a model.
    ///
    /// Active alerts make it a concern; a volatile trend makes it a watch; otherwise it is nominal.
    /// Every provider uses this rule, so a model can phrase an insight but can't escalate one: it is
    /// never told the thresholds, so any severity it picked would have no grounding.
    public var advisorySeverity: InsightSeverity {
        if activeAlertCount > 0 { return .concern }
        return statistics.trend == .volatile ? .watch : .nominal
    }
}
