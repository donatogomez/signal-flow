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
            Picker("View", selection: $model.tab) {
                ForEach(AlertTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], Spacing.lg)
            .padding(.bottom, Spacing.sm)

            list
        }
        .navigationTitle("Alerts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Severity", selection: $model.severityFilter) {
                        ForEach(AlertSeverityFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await model.observe() }
    }

    @ViewBuilder
    private var list: some View {
        switch model.phase {
        case .loading where model.active.isEmpty && model.history.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Couldn't load alerts", systemImage: "exclamationmark.triangle", description: Text(message))
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
                ContentUnavailableView("No \(model.severityFilter.title.lowercased()) alerts", systemImage: "line.3.horizontal.decrease.circle")
            } else if model.tab == .active {
                ContentUnavailableView("No active alerts", systemImage: "checkmark.seal", description: Text("Everything in the fleet looks healthy."))
            } else {
                ContentUnavailableView("No alert history", systemImage: "clock.arrow.circlepath", description: Text("Resolved alerts will appear here."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single alert row: severity, message, device/asset context, time, and acknowledge state/action.
private struct AlertRowView: View {
    let row: AlertRow
    let isHistory: Bool
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SeverityTag(row.severity)
                Spacer()
                Text(row.raisedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Label("\(row.deviceName) · \(row.assetName)", systemImage: row.assetKind.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            footer
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var footer: some View {
        if isHistory {
            Label(row.isAcknowledged ? "Resolved · was acknowledged" : "Resolved", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if row.isAcknowledged {
            Label("Acknowledged", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button(action: onAcknowledge) {
                Label("Acknowledge", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
