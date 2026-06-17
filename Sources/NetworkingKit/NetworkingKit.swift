/// NetworkingKit — live remote transport.
///
/// Will hold the `URLSession`-based telemetry transport (WebSocket framing, reconnect) and
/// outbound command delivery. Produces raw transport DTOs; mapping to domain types happens in
/// DataKit, so this module stays free of domain concepts.
///
/// Scaffolding placeholder — no transport yet.
public enum NetworkingKit {
    /// Marker confirming the module compiles and links. Removed once real types land.
    public static let moduleName = "NetworkingKit"
}
