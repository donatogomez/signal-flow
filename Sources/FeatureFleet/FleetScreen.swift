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
                ForEach(0..<6, id: \.self) { _ in
                    FleetRowPlaceholder()
                        .listRowSeparator(.hidden)
                }
            case .failed(let message):
                ContentUnavailableView(loc("Couldn't load the fleet"), systemImage: "exclamationmark.triangle", description: Text(message))
                    .listRowSeparator(.hidden)
            default:
                if model.visibleRows.isEmpty {
                    emptyState.listRowSeparator(.hidden)
                } else {
                    ForEach(model.visibleRows) { row in
                        Button { onOpenDevice(row.id) } label: { FleetRowView(row: row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(loc("Devices"))
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

    /// Distinguishes "the fleet is genuinely empty" from "search/filter excluded everything" — the same
    /// list shape, but honest, helpful copy for each.
    @ViewBuilder
    private var emptyState: some View {
        if model.rows.isEmpty {
            ContentUnavailableView(
                loc("No devices"),
                systemImage: "shippingbox",
                description: Text(loc("Devices will appear here once they report in."))
            )
        } else {
            ContentUnavailableView(
                loc("No matching devices"),
                systemImage: "magnifyingglass",
                description: Text(loc("Try a different search or filter."))
            )
        }
    }
}

/// A single fleet row. Information-dense but scannable: a status-tinted asset glyph leads (health at a
/// glance), identity in the middle, and a shape-based status cue + chevron trail.
struct FleetRowView: View {
    let row: FleetRow

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status tints the leading badge so the list is scannable by health down the left edge;
            // the asset symbol still conveys the device's type.
            IconBadge(row.assetKind.symbol, tint: row.status.tint)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Unhealthy devices read heavier so they stand out; healthy devices recede to regular weight.
                Text(row.deviceName).font(.body.weight(row.status == .nominal ? .regular : .semibold))
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
                            .accessibilityLabel(Text("\(row.activeAlertCount) ") + Text(loc("Alerts")))
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            // Shape-based status cue (distinguishable without color) for the trailing edge.
            Image(systemName: row.status.symbol)
                .foregroundStyle(row.status.tint)
                .accessibilityLabel(row.status.label)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A neutral skeleton row shown while the first fleet load is in flight — grey shapes that match the
/// real row's silhouette, so the list doesn't jump when data arrives.
private struct FleetRowPlaceholder: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.icon, style: .continuous)
                .fill(.quaternary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Capsule().fill(.quaternary).frame(width: 150, height: 11)
                Capsule().fill(.quaternary).frame(width: 96, height: 9)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityHidden(true)
    }
}
