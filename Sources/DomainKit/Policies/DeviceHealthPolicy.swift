/// Derives a device's ``DeviceStatus`` from its connectivity and currently active alerts.
///
/// This is the single source of truth for "is this device OK?" — a pure, deterministic function with
/// no I/O, so the business judgement is exhaustively testable. Status is always derived here and
/// never stored on the device, so it can't drift out of sync with the underlying facts.
public enum DeviceHealthPolicy {
    public static func status(
        connectivity: ConnectivityStatus,
        activeAlerts: [Alert]
    ) -> DeviceStatus {
        guard connectivity.state != .offline else { return .offline }

        let worstUnacknowledged = activeAlerts
            .filter { !$0.isAcknowledged }
            .map(\.severity)
            .max()

        switch worstUnacknowledged {
        case .critical: return .critical
        case .warning: return .warning
        case .info, .none: return connectivity.state == .degraded ? .warning : .nominal
        }
    }
}
