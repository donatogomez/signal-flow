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
                        AlertRowView(row: row, isHistory: model.tab == .history) {
                            Task { await model.acknowledge(row.id) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        Group {
            if model.severityFilter != .all {
                ContentUnavailableView(loc("No alerts match this filter"), systemImage: "line.3.horizontal.decrease.circle")
            } else if model.tab == .active {
                ContentUnavailableView(loc("No active alerts"), systemImage: "checkmark.seal", description: Text(loc("Everything in the fleet looks healthy.")))
            } else {
                ContentUnavailableView(loc("No alert history"), systemImage: "clock.arrow.circlepath", description: Text(loc("Resolved alerts will appear here.")))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single alert row: a leading severity badge (scannable by shape + colour), the message, device/asset
/// context, time, and the acknowledge state/action. Resolved or acknowledged alerts go visually quiet
/// (neutral badge, muted severity) while staying fully readable, so unacknowledged alerts stand out.
private struct AlertRowView: View {
    let row: AlertRow
    let isHistory: Bool
    let onAcknowledge: () -> Void

    /// Quiet once the alert no longer needs attention — acknowledged, or anything in History.
    private var quiet: Bool { row.isAcknowledged || isHistory }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconBadge(row.severity.symbol, tint: quiet ? .secondary : row.severity.tint)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.severity.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        Spacer()
                        Text(row.raisedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(row.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text(verbatim: "\(row.deviceName) · \(row.assetName)")
                    } icon: {
                        Image(systemName: row.assetKind.symbol)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                footer
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var footer: some View {
        if isHistory {
            Label(row.isAcknowledged ? loc("Resolved · was acknowledged") : loc("Resolved"), systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if row.isAcknowledged {
            Label(loc("Acknowledged"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button(action: onAcknowledge) {
                Label(loc("Acknowledge"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
