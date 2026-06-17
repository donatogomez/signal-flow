/// SimulationKit — deterministic telemetry simulation.
///
/// Will hold the seeded, clock-driven telemetry generator that powers the zero-backend demo and
/// doubles as a reproducible integration-test fixture (see ADR-0003). Same transport shape as the
/// live source, so the rest of the app can't tell them apart.
///
/// Scaffolding placeholder — no generator yet.
public enum SimulationKit {
    /// Marker confirming the module compiles and links. Removed once real types land.
    public static let moduleName = "SimulationKit"
}
