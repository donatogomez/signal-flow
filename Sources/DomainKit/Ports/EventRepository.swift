/// Read access to discrete device events (door open/close, connectivity changes, threshold breaches…).
///
/// Events are distinct from alerts: an event is a timestamped fact a device reported, whereas an
/// `Alert` is a raised, acknowledgeable condition. The UI surfaces a "recent events" feed, so this
/// port exists to serve it through a domain contract rather than exposing a data-source detail.
public protocol EventRepository: Sendable {
    /// The most recent events for one device, newest first.
    func recentEvents(forDevice deviceID: DeviceID, limit: Int) async throws -> [DeviceEvent]
    /// The most recent events across the whole fleet, newest first.
    func recentEvents(limit: Int) async throws -> [DeviceEvent]
}
