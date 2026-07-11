import Foundation
import Observation
import DomainKit

/// The dashboard's state: aggregated fleet figures plus a recent-events feed, both derived from
/// `DomainKit` ports. `@Observable` + `@MainActor` for the same reasons as the fleet model.
@MainActor
@Observable
public final class DashboardModel {
    public enum Phase: Sendable, Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var stats: FleetStats = .empty
    public private(set) var recentEvents: [EventRow] = []

    private let fetchFleetOverview: FetchFleetOverviewUseCase
    private let events: any EventRepository

    /// When each event was first seen this session. `DeviceEvent.occurredAt` is in the simulated 600× clock
    /// (events can be sim-years old), so wall-time "X ago" reads "hace 3 años"; instead age them by how long
    /// they've actually been on screen. Pruned as events roll off.
    private var eventFirstSeen: [EventID: Date] = [:]

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        events: any EventRepository
    ) {
        self.fetchFleetOverview = FetchFleetOverviewUseCase(assets: assets, devices: devices, alerts: alerts)
        self.events = events
    }

    public func refresh() async {
        do {
            let fleet = try await fetchFleetOverview()
            stats = Self.stats(from: fleet)

            let namesByID = Dictionary(
                fleet.flatMap(\.devices).map { ($0.device.id, $0.device.name) },
                uniquingKeysWith: { first, _ in first }
            )
            recentEvents = try await events.recentEvents(limit: 12).map { event in
                EventRow(
                    id: event.id,
                    kind: event.kind,
                    deviceName: namesByID[event.deviceID] ?? "Device",
                    occurredAt: event.occurredAt
                )
            }
            reconcileEventFirstSeen()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// When the given event first appeared this session — the anchor for its real-time "hace X" age.
    public func firstSeen(event id: EventID) -> Date { eventFirstSeen[id] ?? Date() }

    private func reconcileEventFirstSeen(now: Date = Date()) {
        let ids = Set(recentEvents.map(\.id))
        eventFirstSeen = eventFirstSeen.filter { ids.contains($0.key) }
        for id in ids where eventFirstSeen[id] == nil { eventFirstSeen[id] = now }
    }

    public func observe(interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) } catch { break }
        }
    }

    /// Pure aggregation — folds the fleet overview into the dashboard's headline figures.
    static func stats(from fleet: [FleetOverview]) -> FleetStats {
        var stats = FleetStats()
        stats.assetCount = fleet.count
        for summary in fleet.flatMap(\.devices) {
            stats.totalDevices += 1
            if summary.device.connectivity.state == .offline { stats.offline += 1 } else { stats.online += 1 }
            stats.activeAlerts += summary.activeAlertCount
            switch summary.status {
            case .nominal: stats.nominal += 1
            case .warning: stats.warning += 1
            case .critical: stats.critical += 1
            case .offline: break
            }
        }
        return stats
    }
}
