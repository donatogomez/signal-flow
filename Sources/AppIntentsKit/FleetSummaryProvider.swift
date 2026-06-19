import Foundation
import SnapshotKit

/// The data abstraction the "Show Fleet Summary" intent reads through.
///
/// It exists so the intent depends on a *small, domain-facing* contract rather than on PersistenceKit
/// (or, worse, the live data engine). The live implementation reads the persisted snapshot; tests
/// inject a fake. Registered with `AppDependencyManager` and resolved via `@Dependency` in the intent.
public protocol FleetSummaryProviding: Sendable {
    func currentSummary() async throws -> FleetSummary
}

/// Live provider: reads the latest persisted snapshot via SnapshotKit (PersistenceKit → SwiftData).
public struct PersistedFleetSummaryProvider: FleetSummaryProviding {
    private let makeReader: @Sendable () throws -> WidgetSnapshotReader

    /// Default: read the shared App Group store.
    public init() {
        self.makeReader = { try WidgetSnapshotReader.shared() }
    }

    /// Test seam: read through an injected reader (e.g. one over an in-memory store).
    public init(reader: WidgetSnapshotReader) {
        self.makeReader = { reader }
    }

    public func currentSummary() async throws -> FleetSummary {
        try await makeReader().read().fleet
    }
}

/// The dependency seam for the data intent.
///
/// App Intents' own `@Dependency` resolves poorly for protocol existentials (it traps when the
/// registered concrete type doesn't match the declared `any` type), so we use a tiny `@MainActor`
/// holder instead: process-global, isolation-safe (no `@unchecked`), and trivially overridable by the
/// app at launch and by tests. Intents run in the app process, so this is the same instance the app set.
@MainActor
public enum AppIntentsEnvironment {
    public static var fleetSummaryProvider: any FleetSummaryProviding = PersistedFleetSummaryProvider()
}

public extension FleetSummary {
    /// A natural-language one-liner for Siri/Shortcuts dialog and the intent's returned value.
    var spokenSummary: String {
        guard total > 0 else { return "No devices are reporting yet." }

        var parts = ["\(online) of \(total) devices online"]
        if critical > 0 { parts.append("\(critical) critical") }
        if warning > 0 { parts.append("\(warning) warning") }
        if offline > 0 { parts.append("\(offline) offline") }
        return parts.joined(separator: ", ") + "."
    }
}
