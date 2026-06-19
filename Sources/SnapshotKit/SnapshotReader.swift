import Foundation
import DomainKit
import PersistenceKit

/// Reads glance-surface data from **persisted state only**.
///
/// This is the architectural keystone for both widgets and App Intents: neither ever touches
/// `DataKit`, `SimulationKit`, or `NetworkingKit`. This reader loads the last snapshot the app
/// committed to SwiftData through PersistenceKit's `PersistenceStoring` port (a `ModelActor`) and
/// aggregates it into a ``WidgetData``. Out-of-process surfaces open the *same* App Group store, so this
/// is genuinely the app's data — just observed read-only.
public struct WidgetSnapshotReader: Sendable {
    private let store: any PersistenceStoring
    private let alertLimit: Int

    /// Injectable store — tests pass an in-memory `PersistenceStore`; surfaces use the shared one.
    public init(store: any PersistenceStoring, alertLimit: Int = 6) {
        self.store = store
        self.alertLimit = alertLimit
    }

    /// Builds a reader over the shared App Group store. Used by the widget extension and App Intents.
    public static func shared(alertLimit: Int = 6) throws -> WidgetSnapshotReader {
        WidgetSnapshotReader(store: try PersistenceController.makeSharedStore(), alertLimit: alertLimit)
    }

    /// Loads the persisted snapshot and aggregates it. `now` is injected so timeline/snapshot tests are
    /// deterministic.
    public func read(now: Date = Date()) async throws -> WidgetData {
        let snapshot = try await store.loadSnapshot()
        return WidgetData(
            fleet: FleetSummary.make(from: snapshot),
            alerts: WidgetAlert.top(from: snapshot, limit: alertLimit),
            generatedAt: now
        )
    }
}

/// The single entry point glance surfaces call. It builds the shared reader and degrades to an empty
/// (but valid) payload if persisted state can't be read — a widget or intent must always produce
/// something.
public enum WidgetDataLoader {
    public static func load(now: Date) async -> WidgetData {
        guard let reader = try? WidgetSnapshotReader.shared() else { return .empty(now: now) }
        return (try? await reader.read(now: now)) ?? .empty(now: now)
    }
}
