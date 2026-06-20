import SwiftUI
import DomainKit
import DesignSystemKit

/// The fleet list: every device with its asset, status, connectivity, battery, and alert count, with
/// search, sort, and filter. Built to read like Apple's own list screens — plain list, native search,
/// a single options menu.
public struct FleetScreen: View {
    @State private var model: FleetModel
    private let onOpenDevice: (DeviceID) -> Void

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        onOpenDevice: @escaping (DeviceID) -> Void = { _ in }
    ) {
        _model = State(initialValue: FleetModel(assets: assets, devices: devices, alerts: alerts))
        self.onOpenDevice = onOpenDevice
    }

    public var body: some View {
        @Bindable var model = model
        List {
            switch model.phase {
            case .loading where model.rows.isEmpty:
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            case .failed(let message):
                ContentUnavailableView(loc("Couldn't load the fleet"), systemImage: "exclamationmark.triangle", description: Text(message))
            default:
                if model.visibleRows.isEmpty {
                    ContentUnavailableView(loc("No matching devices"), systemImage: "magnifyingglass")
                } else {
                    ForEach(model.visibleRows) { row in
                        Button { onOpenDevice(row.id) } label: { FleetRowView(row: row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(loc("Fleet"))
        .searchable(text: $model.searchText, prompt: Text(loc("Search devices or assets")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(loc("Sort"), selection: $model.sort) {
                        ForEach(FleetSort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(loc("Filter"), selection: $model.statusFilter) {
                        ForEach(FleetStatusFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(loc("Sort & filter"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await model.observe() }
    }
}

/// A single fleet row. Information-dense but scannable: identity on the left, status on the right.
struct FleetRowView: View {
    let row: FleetRow

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: row.assetKind.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(row.deviceName).font(.body.weight(.medium))
                Text(verbatim: "\(row.assetName) · \(row.assetKind.localizedName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: Spacing.lg) {
                    ConnectivityLabel(row.connectivity)
                    BatteryLabel(row.battery)
                    if row.activeAlertCount > 0 {
                        Label("\(row.activeAlertCount)", systemImage: "bell.badge.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: row.status.symbol)
                .foregroundStyle(row.status.tint)
                .accessibilityLabel(row.status.label)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }
}
