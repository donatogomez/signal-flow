/// TestingSupportKit — shared test utilities.
///
/// Will hold the reusable test doubles (fakes/stubs conforming to DomainKit ports), data builders,
/// fixtures, and the deterministic clock/RNG that make concurrency tests reproducible. The same
/// utilities also power SwiftUI previews via the composition root's `.preview()` container.
///
/// Intentionally **empty** during scaffolding — only the module marker exists so far.
public enum TestingSupportKit {
    /// Marker confirming the module compiles and links. Removed once real utilities land.
    public static let moduleName = "TestingSupportKit"
}
