import FoundationModels

/// The structured shape the on-device model fills in via **guided generation**.
///
/// Using `@Generable` + `@Guide` means the framework returns a typed value, not free-form text we'd
/// have to parse — there is no `JSONSerialization`, no fragile string handling. The draft is mapped to
/// the framework-free `DeviceInsight` before it ever leaves this module. There is deliberately no
/// severity field: the model is never given thresholds, so severity is decided in Swift
/// (`InsightContext.advisorySeverity`), not generated.
@Generable
struct InsightDraft {
    @Guide(description: "Two or three sentences summarizing the recent telemetry in plain language. Do not invent or estimate any numbers.")
    var summary: String

    @Guide(description: "A brief, hypothetical explanation of any anomaly, using words like 'likely' or 'may'. If nothing is unusual, say so plainly.")
    var anomalyExplanation: String

    @Guide(description: "One concrete, conservative operational recommendation.")
    var recommendation: String
}
