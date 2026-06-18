import Foundation
import SwiftData

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

    /// An on-disk container for the running app.
    public static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// An in-memory container for tests and previews — deterministic, leaves no files on disk.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
