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

    /// A request cancelled while the base provider was working records nothing: nobody will see that
    /// result, so it would only add a stale entry to the history.
    func insight(for context: InsightContext) async throws -> DeviceInsight {
        let result = try await base.insight(for: context)
        try Task.checkCancellation()
        let record = InsightRecord(
            deviceID: context.deviceID, metric: context.metric, insight: result, createdAt: Date()
        )
        await store.recordInsight(record)
        do {
            try await persistence.appendInsight(record)
        } catch {
            // Still in the in-memory history for this session; not retried (insights are regenerated).
            Log.persistence.error("Saving an insight failed: \(String(describing: error), privacy: .private)")
        }
        return result
    }
}
