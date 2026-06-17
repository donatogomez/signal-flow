/// DomainKit — the pure business core.
///
/// Will hold entities, value objects, policies, domain errors, and the repository/service
/// **ports** (protocols) that outer layers implement. This target imports nothing but the
/// Swift standard library and **must not depend on any other SignalFlow target** — that purity
/// is what makes the business logic testable in isolation and is enforced by the build graph.
///
/// Scaffolding placeholder — no entities, value objects, or ports yet.
public enum DomainKit {
    /// Marker confirming the module compiles and links. Removed once real types land.
    public static let moduleName = "DomainKit"
}
