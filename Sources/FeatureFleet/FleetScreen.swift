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
        VStack(spacing: 0) {
            // Status filter is visible up front as chips (not hidden in a menu), so the active filter is
            // always on screen and one tap away.
            FilterChips(
                FleetStatusFilter.allCases,
                selection: $model.statusFilter,
                label: { $0.title },
                symbol: { $0.chipSymbol },
                tint: { $0.chipTint }
            )
            .padding(.vertical, Spacing.sm)

            list
        }
        .navigationTitle(loc("Devices"))
        .searchable(text: $model.searchText, prompt: Text(loc("Search devices or assets")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(loc("Sort"), selection: $model.sort) {
                        ForEach(FleetSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(loc("Sort"), systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task { await model.observe() }
    }

    /// The list, grouped attention-first: devices that need looking at, then the healthy ones (which
    /// recede). Each group keeps the model's current sort order. A specific status filter collapses to the
    /// single relevant group.
    private var list: some View {
        let visible = model.visibleRows
        let attention = visible.filter { $0.status != .nominal }
        let healthy = visible.filter { $0.status == .nominal }
        return List {
            switch model.phase {
            case .loading where model.rows.isEmpty:
                ForEach(0..<6, id: \.self) { _ in
                    FleetRowPlaceholder().listRowSeparator(.hidden)
                }
            case .failed(let message):
                ContentUnavailableView(loc("Couldn't load the fleet"), systemImage: "exclamationmark.triangle", description: Text(message))
                    .listRowSeparator(.hidden)
            default:
                if visible.isEmpty {
                    emptyState.listRowSeparator(.hidden)
                } else {
                    if !attention.isEmpty {
                        Section(loc("Needs attention")) {
                            ForEach(attention) { deviceRow($0) }
                        }
                    }
                    if !healthy.isEmpty {
                        Section(loc("Healthy")) {
                            ForEach(healthy) { deviceRow($0) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func deviceRow(_ row: FleetRow) -> some View {
        Button { onOpenDevice(row.id) } label: { FleetRowView(row: row) }
            .buttonStyle(.plain)
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

/// A single fleet row, built for one-second scanning: a status glyph (shape + semantic tint) leads, the
/// device name and its asset sit in the middle, and an alert-count badge trails. The status word lives in
/// the VoiceOver label (not duplicated on screen).
struct FleetRowView: View {
    let row: FleetRow

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(row.status.symbol, tint: row.status.tint)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Unhealthy devices read heavier so they stand out; healthy devices recede to regular weight.
                Text(row.deviceName)
                    .font(.body.weight(row.status == .nominal ? .regular : .semibold))
                Text(row.assetName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            if row.activeAlertCount > 0 {
                Label("\(row.activeAlertCount)", systemImage: "bell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.deviceName), \(row.status.label), \(row.assetName)")
        .accessibilityValue(row.activeAlertCount > 0 ? loc("\(row.activeAlertCount) active alerts") : "")
    }
}

/// Chip styling for the status filter: each status filter carries its `DeviceStatus` glyph + tint so the
/// chips read by shape and colour; "All" is the neutral accent.
private extension FleetStatusFilter {
    var chipSymbol: String? {
        switch self {
        case .all: nil
        case .nominal: DeviceStatus.nominal.symbol
        case .warning: DeviceStatus.warning.symbol
        case .critical: DeviceStatus.critical.symbol
        case .offline: DeviceStatus.offline.symbol
        }
    }

    var chipTint: Color {
        switch self {
        case .all: .accentColor
        case .nominal: DeviceStatus.nominal.tint
        case .warning: DeviceStatus.warning.tint
        case .critical: DeviceStatus.critical.tint
        case .offline: DeviceStatus.offline.tint
        }
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
