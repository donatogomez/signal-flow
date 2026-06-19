/// Read access to **resolved** alerts — the history of past incidents.
///
/// `AlertRepository` only exposes *currently active* alerts (the ones still firing). A history list
/// needs the alerts that have since cleared, which no existing port provides — hence this focused,
/// additive port. It's implemented by the data layer, which archives an alert when its condition
/// recovers, preserving any acknowledgement it carried.
public protocol AlertHistoryProviding: Sendable {
    /// Resolved alerts across the fleet, newest first, capped at `limit`.
    func alertHistory(limit: Int) async throws -> [Alert]
}
