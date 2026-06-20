#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI
import DomainKit
import DesignSystemKit
import SnapshotKit
import LiveActivityKit

/// The **critical-alert Live Activity**: a Lock Screen / StandBy card plus the Dynamic Island in its
/// compact, minimal, and expanded presentations. Lives in the widget extension's bundle (this module is
/// linked by `SignalFlowWidgets`). Guarded by `#if os(iOS)` since ActivityKit is iOS-only.
///
/// It renders only the deterministic ``CriticalAlertState`` handed to it by ActivityKit — it makes no
/// decisions and reads no data of its own.
public struct CriticalAlertLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CriticalAlertActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.red.opacity(0.12))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.attributes.deepLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Critical", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.severity.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusBadge(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.deviceName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(context.state.reason)
                            .font(.subheadline)
                            .lineLimit(2)
                        if let asset = context.state.assetName {
                            Text("\(asset) · since \(context.state.startedAt, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Since \(context.state.startedAt, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(context.state.severity.tint)
            } compactTrailing: {
                Text(context.state.deviceName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(context.state.severity.tint)
            }
            .widgetURL(context.attributes.deepLink.url)
            .keylineTint(context.state.severity.tint)
        }
    }
}

// MARK: - Lock Screen / StandBy

private struct LockScreenView: View {
    let state: CriticalAlertState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label(state.severity.label, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.severity.tint)
                Spacer()
                StatusBadge(status: state.status)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(state.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                if let asset = state.assetName {
                    Text(asset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(state.reason)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Since \(state.startedAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.md)
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    let status: AlertActivityStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .active: .red
        case .acknowledged: .orange
        case .resolved: .green
        }
    }
}
#endif
