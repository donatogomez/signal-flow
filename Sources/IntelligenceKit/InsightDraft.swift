import FoundationModels
import DomainKit

/// The structured shape the on-device model fills in via **guided generation**.
///
/// Using `@Generable` + `@Guide` means the framework returns a typed value, not free-form text we'd
/// have to parse — there is no `JSONSerialization`, no fragile string handling. The draft is mapped to
/// the framework-free `DeviceInsight` before it ever leaves this module.
@Generable
struct InsightDraft {
    @Guide(description: "Two or three sentences summarizing the recent telemetry in plain language. Do not invent or estimate any numbers.")
    var summary: String

    @Guide(description: "A brief, hypothetical explanation of any anomaly, using words like 'likely' or 'may'. If nothing is unusual, say so plainly.")
    var anomalyExplanation: String

    @Guide(description: "One concrete, conservative operational recommendation.")
    var recommendation: String

    @Guide(description: "Advisory noteworthiness only — not a safety verdict.")
    var severity: DraftSeverity
}

/// Advisory severity the model classifies. Mapped to `DomainKit.InsightSeverity`; deliberately distinct
/// from the deterministic `AlertSeverity` / `DeviceStatus` that govern actual safety state.
@Generable
enum DraftSeverity {
    case nominal
    case watch
    case concern
}

extension DraftSeverity {
    var domain: InsightSeverity {
        switch self {
        case .nominal: .nominal
        case .watch: .watch
        case .concern: .concern
        }
    }
}
