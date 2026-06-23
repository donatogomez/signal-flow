import Foundation
import SnapshotKit

/// Localized, glanceable presentation strings for the watch complication / Smart Stack widget.
///
/// Cross-platform (no WidgetKit) so the composed text is unit-tested on the macOS host; Spanish is
/// asserted against the shipped catalog. The view layer reads these strings; it never composes copy
/// itself.
public struct WatchComplicationViewModel: Equatable, Sendable {
    private let entry: WatchComplicationEntry

    public init(_ entry: WatchComplicationEntry) {
        self.entry = entry
    }

    public var online: Int { entry.online }
    public var warning: Int { entry.warning }
    public var critical: Int { entry.critical }
    public var total: Int { entry.total }
    public var hasData: Bool { entry.hasData }
    public var isStale: Bool { entry.isStale }
    public var referenceDate: Date? { entry.referenceDate }
    public var topAlertDeviceName: String? { entry.topAlert?.deviceName }
    public var topAlertMessage: String? { entry.topAlert?.message }

    /// "2 critical" — localized, pluralized in the compiled app.
    public var criticalText: String { loc("\(critical) critical") }
    /// "2 warnings" — localized, pluralized in the compiled app.
    public var warningText: String { loc("\(warning) warning") }
    /// "8/10 online" — localized ("8/10 en línea").
    public var onlineText: String { loc("\(online)/\(total) online") }
    /// The "Stale" badge text, shown when the synced data is older than the threshold.
    public var staleText: String { loc("Stale") }

    /// The headline status line, severity-first:
    /// - no data → "No data"
    /// - criticals → "2 critical · 8/10 online"
    /// - warnings → "2 warnings"
    /// - otherwise → "All nominal"
    public var statusLine: String {
        guard hasData else { return loc("No data") }
        if critical > 0 { return "\(criticalText) · \(onlineText)" }
        if warning > 0 { return warningText }
        return loc("All nominal")
    }

    /// A very short status for the smallest families (circular / corner): the worst count, "✓" when all
    /// nominal, or "—" with no data.
    public var compactCount: String {
        guard hasData else { return "—" }
        if critical > 0 { return "\(critical)" }
        if warning > 0 { return "\(warning)" }
        return "\(online)"
    }

    /// Accessibility-friendly tint role, severity-first. The view maps this to a concrete colour.
    public enum Tone: Equatable, Sendable { case critical, warning, nominal, neutral }
    public var tone: Tone {
        guard hasData else { return .neutral }
        if critical > 0 { return .critical }
        if warning > 0 { return .warning }
        return .nominal
    }
}
