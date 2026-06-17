/// FeatureInsights — the on-device AI insight surface.
///
/// Will hold the views, presentation models, and routes for trend summaries, anomaly explanations,
/// and the fleet digest. Talks to the Foundation Models layer only through the DomainKit
/// `InsightService` port, so it stays free of the `FoundationModels` framework. Depends only on
/// DomainKit and DesignSystemKit.
///
/// Scaffolding placeholder — no screens yet.
public enum FeatureInsights {
    /// Marker confirming the module compiles and links. Removed once real views land.
    public static let moduleName = "FeatureInsights"
}
