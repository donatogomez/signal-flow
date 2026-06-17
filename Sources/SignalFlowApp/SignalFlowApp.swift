/// SignalFlowApp — the composition root.
///
/// The only target allowed to know concrete types. It will build the dependency-injection container
/// (binding DataKit/PersistenceKit/NetworkingKit/SimulationKit implementations to DomainKit ports),
/// assemble the feature modules, and own top-level navigation. The actual iOS app shell (an Xcode
/// app target with `@main`) is a thin wrapper that links this module and hands off to it.
///
/// Scaffolding placeholder — no wiring yet.
public enum SignalFlowApp {
    /// Marker confirming the composition root compiles and links every module it depends on.
    public static let moduleName = "SignalFlowApp"
}
