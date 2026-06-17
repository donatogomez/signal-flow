/// FeatureDashboard — the at-a-glance home surface.
///
/// Will hold the SwiftUI views, `@Observable` presentation models, and navigation routes for the
/// dashboard. Depends only on DomainKit (entities + ports) and DesignSystemKit; repositories arrive
/// via injected protocols, so this module cannot — and must not — import the data layer.
///
/// Scaffolding placeholder — no screens yet.
public enum FeatureDashboard {
    /// Marker confirming the module compiles and links. Removed once real views land.
    public static let moduleName = "FeatureDashboard"
}
