/// PersistenceKit — local storage.
///
/// Will hold the SwiftData stack: `@Model` record types, the `ModelActor`-backed store,
/// migration plan, and retention. Records never leave this layer — DataKit maps them to and
/// from domain entities at the boundary.
///
/// Scaffolding placeholder — no models or store yet.
public enum PersistenceKit {
    /// Marker confirming the module compiles and links. Removed once real types land.
    public static let moduleName = "PersistenceKit"
}
