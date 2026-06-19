import Foundation
import DomainKit
import PersistenceKit

/// Reads the widgets' data from **persisted state only**.
///
/// This is the heart of requirement #3: the widget never touches `DataKit`, `SimulationKit`, or
/// `NetworkingKit`. It reads the last snapshot the app committed to SwiftData through PersistenceKit's
/// `PersistenceStoring` port (a `ModelActor`), and aggregates it into a ``WidgetData``. The widget
/// process and the app process open the *same* App Group store, so this is genuinely the app's data —
/// just observed from another process, read-only.
public struct WidgetSnapshotReader: Sendable {
    private let store: any PersistenceStoring
    private let alertLimit: Int

    /// Injectable store — tests pass an in-memory `PersistenceStore`; the extension uses the shared one.
    public init(store: any PersistenceStoring, alertLimit: Int = 6) {
        self.store = store
        self.alertLimit = alertLimit
    }

    /// Builds a reader over the shared App Group store. Used by the widget extension at runtime.
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

/// The single entry point both providers call. It builds the shared reader and degrades to an empty
/// (but valid) payload if persisted state can't be read — a widget must always render something.
enum WidgetDataLoader {
    static func load(now: Date) async -> WidgetData {
        guard let reader = try? WidgetSnapshotReader.shared() else { return .empty(now: now) }
        return (try? await reader.read(now: now)) ?? .empty(now: now)
    }
}
