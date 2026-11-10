/// Where the data layer's startup stands, as the root view presents it.
///
/// It describes the bootstrap (catalog and restore), not ingestion: once startup succeeds, the
/// state stays put while scene-phase changes stop and restart ingestion.
public enum StartupState: Sendable, Equatable {
    /// No start has been requested yet.
    case notStarted
    /// A bootstrap is in progress.
    case starting
    /// Started with everything available.
    case ready
    /// Started and usable, with a capability missing.
    case degraded(Degradation)
    /// The bootstrap failed. Nothing was ingested; a later start request tries again.
    case failed

    public enum Degradation: Sendable, Equatable {
        /// The on-disk store couldn't be opened: telemetry stays in memory and nothing is saved, so
        /// widgets and the next launch won't see this session's data.
        case persistenceUnavailable
        /// The saved snapshot couldn't be restored: the session runs on fresh telemetry only.
        case restoreFailed
    }
}
