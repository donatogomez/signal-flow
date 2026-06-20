import SwiftUI
import DomainKit
import SnapshotKit

/// The watch app's root: a `NavigationStack` over the Fleet Summary, which drills into Alerts and then a
/// per-device snapshot. The whole tree is driven by a single ``WatchStore`` and reads only persisted
/// state — no business logic lives here.
public struct WatchRootView: View {
    @State private var store: WatchStore

    public init(store: WatchStore = WatchStore()) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        NavigationStack {
            FleetSummaryScreen(store: store)
        }
        .task { await store.refresh() }
    }
}

// MARK: - Fleet Summary

struct FleetSummaryScreen: View {
    let store: WatchStore

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView()
            case .loaded where !store.hasData:
                WatchEmptyState()
            case .loaded:
                loaded
            }
        }
        .navigationTitle("Fleet")
    }

    private var loaded: some View {
        let fleet = store.fleet
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fleet.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(fleet.critical > 0 ? .red : (fleet.warning > 0 ? .orange : .green))
                    Text("\(fleet.online)/\(fleet.total) online")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                StatRow(symbol: "checkmark.circle.fill", tint: .green, label: "Online", value: fleet.online)
                StatRow(symbol: "exclamationmark.triangle.fill", tint: .orange, label: "Warning", value: fleet.warning)
                StatRow(symbol: "exclamationmark.octagon.fill", tint: .red, label: "Critical", value: fleet.critical)
                if fleet.offline > 0 {
                    StatRow(symbol: "wifi.slash", tint: .secondary, label: "Offline", value: fleet.offline)
                }
            }

            if fleet.hasAlerts {
                NavigationLink {
                    CriticalAlertsScreen(store: store)
                } label: {
                    Label("\(fleet.alertCount) active \(fleet.alertCount == 1 ? "alert" : "alerts")", systemImage: "bell.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private struct StatRow: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Label(label, systemImage: symbol)
                .foregroundStyle(tint)
            Spacer()
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: - Critical Alerts

struct CriticalAlertsScreen: View {
    let store: WatchStore

    var body: some View {
        let model = store.alertList
        Group {
            if model.isEmpty {
                ContentUnavailableView("No active alerts", systemImage: "checkmark.seal.fill")
            } else {
                List(model.alerts) { alert in
                    NavigationLink(value: alert) {
                        AlertRow(alert: alert)
                    }
                }
                .navigationDestination(for: WidgetAlert.self) { alert in
                    DeviceSnapshotScreen(alert: alert)
                }
            }
        }
        .navigationTitle("Alerts")
    }
}

private struct AlertRow: View {
    let alert: WidgetAlert

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: alert.severity.watchSymbol)
                .foregroundStyle(alert.severity.watchTint)
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                Text(alert.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Device Snapshot

struct DeviceSnapshotScreen: View {
    let alert: WidgetAlert

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.deviceName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Label(alert.severity.watchLabel, systemImage: alert.severity.watchSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(alert.severity.watchTint)
                }
            }
            Section("Reason") {
                Text(alert.message)
                    .font(.body)
            }
            Section {
                LabeledContent("Since", value: alert.raisedAt, format: .relative(presentation: .named))
            }
        }
        .navigationTitle("Device")
    }
}

// MARK: - Empty state

struct WatchEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No fleet data", systemImage: "iphone.gen3")
        } description: {
            Text("Open SignalFlow on your iPhone to sync fleet status to your watch.")
        }
    }
}

// MARK: - Severity styling (watch-local, no DesignSystemKit dependency)

private extension AlertSeverity {
    var watchTint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    var watchLabel: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var watchSymbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
