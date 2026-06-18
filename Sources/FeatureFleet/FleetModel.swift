import Foundation
import Observation
import DomainKit

/// The fleet screen's state, driven entirely by `DomainKit` ports.
///
/// `@Observable` (not `ObservableObject`) gives SwiftUI fine-grained dependency tracking — a view that
/// reads only `searchText` re-renders when search changes but not when the rows reload. `@MainActor`
/// keeps all UI state mutation on the main actor; the repository work hops off it via `async`.
@MainActor
@Observable
public final class FleetModel {
    public enum Phase: Sendable, Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var rows: [FleetRow] = []

    // User-controlled query state — bound directly to the toolbar and search field.
    public var searchText: String = ""
    public var sort: FleetSort = .status
    public var statusFilter: FleetStatusFilter = .all

    private let fetchFleetOverview: FetchFleetOverviewUseCase

    public init(assets: any AssetRepository, devices: any DeviceRepository, alerts: any AlertRepository) {
        self.fetchFleetOverview = FetchFleetOverviewUseCase(assets: assets, devices: devices, alerts: alerts)
    }

    /// The data the view actually renders: filtered, searched, and sorted. Computed so SwiftUI
    /// recomputes it automatically whenever the inputs it touches change.
    public var visibleRows: [FleetRow] {
        rows
            .filter { statusFilter.matches($0.status) }
            .filter { matchesSearch($0) }
            .sorted(by: sort.areInOrder)
    }

    private func matchesSearch(_ row: FleetRow) -> Bool {
        guard !searchText.isEmpty else { return true }
        return row.deviceName.localizedCaseInsensitiveContains(searchText)
            || row.assetName.localizedCaseInsensitiveContains(searchText)
    }

    /// Loads the fleet once.
    public func refresh() async {
        do {
            let fleet = try await fetchFleetOverview()
            rows = fleet.flatMap { overview in
                overview.devices.map { summary in
                    FleetRow(
                        id: summary.device.id,
                        deviceName: summary.device.name,
                        assetName: overview.asset.name,
                        assetKind: overview.asset.kind,
                        status: summary.status,
                        connectivity: summary.device.connectivity.state,
                        battery: summary.device.battery,
                        activeAlertCount: summary.activeAlertCount
                    )
                }
            }
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Keeps the fleet fresh while the screen is visible. Driven by `.task`, so it is cancelled the
    /// moment the view disappears — structured concurrency tied to the view lifecycle.
    public func observe(interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) } catch { break }
        }
    }
}
