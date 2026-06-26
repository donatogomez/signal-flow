import SwiftUI
import DomainKit
import DesignSystemKit

/// The Alerts surface: an Active / History segmented switch, a severity filter, and a list of alerts
/// with device/asset context and an acknowledge action. Severity-first ordering and a native list
/// keep it readable and information-dense, in line with Apple's own list screens.
public struct AlertsScreen: View {
    @State private var model: AlertsModel

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        alertHistory: any AlertHistoryProviding
    ) {
        _model = State(initialValue: AlertsModel(assets: assets, devices: devices, alerts: alerts, alertHistory: alertHistory))
    }

    public var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker(loc("View"), selection: $model.tab) {
                ForEach(AlertTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], Spacing.lg)
            .padding(.bottom, Spacing.sm)

            list
        }
        .navigationTitle(loc("Alerts"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(loc("Severity"), selection: $model.severityFilter) {
                        ForEach(AlertSeverityFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    // The icon fills when a filter is applied, so an active filter is visible on screen.
                    Label(loc("Filter"), systemImage: model.severityFilter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task { await model.observe() }
    }

    @ViewBuilder
    private var list: some View {
        switch model.phase {
        case .loading where model.active.isEmpty && model.history.isEmpty:
            List {
                ForEach(0..<6, id: \.self) { _ in
                    AlertRowPlaceholder().listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        case .failed(let message):
            ContentUnavailableView(loc("Couldn't load alerts"), systemImage: "exclamationmark.triangle", description: Text(message))
        default:
            if model.visibleAlerts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.visibleAlerts) { row in
                        AlertRowView(row: row, tab: model.tab) {
                            Task { await model.acknowledge(row.id) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.severityFilter != .all {
            ContentUnavailableView(loc("No alerts match this filter"), systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.tab {
            case .active:
                ContentUnavailableView(loc("No active alerts"), systemImage: "checkmark.seal", description: Text(loc("Everything in the fleet looks healthy.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .acknowledged:
                ContentUnavailableView(loc("No acknowledged alerts"), systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .resolved:
                ContentUnavailableView(loc("No resolved alerts"), systemImage: "clock.arrow.circlepath", description: Text(loc("Resolved alerts will appear here.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A single alert, inbox-style: a leading severity badge (shape + colour), the severity label with the
/// observed value surfaced on the trailing edge, the metric + device context and relative time, then a
/// per-state footer (an Acknowledge action while active; a quiet status label once acknowledged/resolved).
/// Acknowledged and resolved alerts read quieter but stay fully legible.
private struct AlertRowView: View {
    let row: AlertRow
    let tab: AlertTab
    let onAcknowledge: () -> Void

    /// Active alerts are the ones needing action; acknowledged and resolved recede.
    private var quiet: Bool { tab != .active }

    private var accessibilityLabel: String {
        "\(row.severity.label). \(row.message). \(row.deviceName), \(row.assetName)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconBadge(row.severity.symbol, tint: quiet ? .secondary : row.severity.tint)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(row.severity.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        Spacer(minLength: Spacing.sm)
                        Text(row.valueText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(row.severity.tint))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(verbatim: "\(row.metric.localizedName) · \(row.deviceName)")
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        Text(row.raisedAt, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)

                footer
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var footer: some View {
        switch tab {
        case .active:
            Button(action: onAcknowledge) {
                Label(loc("Acknowledge"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .acknowledged:
            Label(loc("Acknowledged"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .resolved:
            Label(row.isAcknowledged ? loc("Resolved · was acknowledged") : loc("Resolved"), systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A neutral skeleton row shown while the first alert load is in flight — matches the real row's
/// silhouette (leading badge + stacked text), consistent with Fleet's loading state.
private struct AlertRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.icon, style: .continuous)
                .fill(.quaternary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Capsule().fill(.quaternary).frame(width: 70, height: 11)
                    Spacer()
                    Capsule().fill(.quaternary).frame(width: 48, height: 9)
                }
                Capsule().fill(.quaternary).frame(height: 11).frame(maxWidth: .infinity)
                Capsule().fill(.quaternary).frame(width: 150, height: 9)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityHidden(true)
    }
}
