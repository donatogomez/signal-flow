/// DataKit — repository implementations.
///
/// The aggregator of the data layer: implements DomainKit's repository/service **ports** on top of
/// NetworkingKit (live), SimulationKit (demo/tests), and PersistenceKit (local store). Owns the
/// mappers, the offline outbox, and sync/reconciliation. This is the only data target the
/// composition root binds into use cases — features never see it.
///
/// Scaffolding placeholder — no repositories yet.
public enum DataKit {
    /// Marker confirming the module compiles and links. Removed once real types land.
    public static let moduleName = "DataKit"
}
