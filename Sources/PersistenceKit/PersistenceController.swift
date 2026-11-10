import Foundation
import SwiftData
import Synchronization

/// Builds the SwiftData `ModelContainer`. The container is `Sendable` and is handed to a
/// ``PersistenceStore`` (a `ModelActor`) which performs all work off the main actor.
public enum PersistenceController {
    static let schema = Schema([
        AssetRecord.self,
        DeviceRecord.self,
        ReadingRecord.self,
        EventRecord.self,
        AlertRecord.self,
        InsightHistoryRecord.self,
    ])

    /// The App Group that the app and its `SignalFlowWidgets` extension share. Both processes open the
    /// **same** on-disk SwiftData store inside this group's container, so the widget reads exactly what
    /// the app persisted — one source of truth, no duplicated storage.
    public static let appGroupIdentifier = "group.com.signalflow.shared"

    /// Filename of the shared store inside the App Group container.
    static let sharedStoreName = "SignalFlow.store"

    /// An on-disk container for the running app.
    public static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        return try makeContainer(configuration)
    }

    /// The on-disk URL of the shared store inside the App Group container, or `nil` when the App Group
    /// is unavailable (e.g. a plain SwiftPM/CLI build with no entitlement).
    public static func sharedStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: sharedStoreName)
    }

    /// A container backed by the shared App Group store. Falls back to the default app-private
    /// container when the App Group isn't reachable, so a CLI build or a misconfigured environment
    /// degrades gracefully instead of throwing.
    public static func makeSharedContainer() throws -> ModelContainer {
        try makeContainer(url: sharedStoreURL())
    }

    /// Convenience for the widget extension: a `PersistenceStore` over the shared App Group container.
    /// Lets the widget read persisted state without ever naming SwiftData itself.
    public static func makeSharedStore() throws -> PersistenceStore {
        PersistenceStore(modelContainer: try makeSharedContainer())
    }

    /// An in-memory container for tests and previews — deterministic, leaves no files on disk.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try makeContainer(configuration)
    }

    /// Containers are created one at a time. Creating stores on two threads at once can crash the
    /// process (issue #30): building a new store's tables, Core Data lazily generates trigger SQL for
    /// its persistent-history entities without synchronization, and those entities are shared by
    /// every container in the process, whatever its schema or configuration. Creation is synchronous
    /// and doesn't call back into this type, so a lock can't deadlock; reads and writes aren't affected.
    private static let creation = Mutex(())

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try creation.withLock { _ in try ModelContainer(for: schema, configurations: configuration) }
    }
}
