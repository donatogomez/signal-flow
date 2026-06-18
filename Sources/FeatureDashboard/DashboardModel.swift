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
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
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
