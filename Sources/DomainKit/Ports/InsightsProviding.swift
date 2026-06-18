/// Produces a ``DeviceInsight`` from a fully-grounded ``InsightContext``.
///
/// Defined with plain domain value types only, so a Foundation Models implementation lives entirely
/// outside the Domain and the deterministic provider can stand in for it — they're interchangeable
/// behind this one port. The composition root chooses which to inject.
public protocol InsightsProviding: Sendable {
    func insight(for context: InsightContext) async throws -> DeviceInsight
}
