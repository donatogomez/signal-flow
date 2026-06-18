import Foundation
import DomainKit
import PersistenceKit

/// Decorates an `InsightsProviding` so every generated insight is recorded — in the in-memory history
/// (for immediate availability) and durably via persistence. The wrapped provider does the real work;
/// this only captures the result, so it composes with either the Foundation Models or deterministic
/// provider transparently.
struct PersistingInsightsProvider: InsightsProviding {
    let base: any InsightsProviding
    let persistence: any PersistenceStoring
    let store: InMemoryTelemetryStore

    func insight(for context: InsightContext) async throws -> DeviceInsight {
        let result = try await base.insight(for: context)
        let record = InsightRecord(
            deviceID: context.deviceID, metric: context.metric, insight: result, createdAt: Date()
        )
        await store.recordInsight(record)
        try? await persistence.appendInsight(record)
        return result
    }
}
