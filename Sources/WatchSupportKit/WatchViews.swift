import SwiftUI
import DomainKit
import SnapshotKit
import WatchConnectivityKit

/// The watch app's root: a `NavigationStack` over the Fleet Summary, which drills into Active Alerts,
/// a Devices list, and a per-device snapshot. The whole tree is driven by a single ``WatchStore`` and
/// reads only persisted/synced state — no business logic lives here.
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

/// Where the Fleet Summary can drill into.
private enum WatchRoute: Hashable {
    case alerts
    case devices
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
        .navigationTitle(loc("Fleet"))
    }

    private var loaded: some View {
        let fleet = store.fleet
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fleet.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(fleet.critical > 0 ? .red : (fleet.warning > 0 ? .orange : .green))
                    Text(fleet.onlineSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let updated = fleet.lastUpdated {
                        Text("\(loc("Updated")) \(updated, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                StatRow(symbol: "checkmark.circle.fill", tint: .green, label: loc("Online"), value: fleet.online)
                StatRow(symbol: "exclamationmark.triangle.fill", tint: .orange, label: loc("Warning"), value: fleet.warning)
                StatRow(symbol: "exclamationmark.octagon.fill", tint: .red, label: loc("Critical"), value: fleet.critical)
                if fleet.offline > 0 {
                    StatRow(symbol: "wifi.slash", tint: .secondary, label: loc("Offline"), value: fleet.offline)
                }
            }

            Section {
                if fleet.hasAlerts {
                    NavigationLink(value: WatchRoute.alerts) {
                        Label(loc("\(fleet.alertCount) active alerts"), systemImage: "bell.fill")
                            .foregroundStyle(.red)
                    }
                }
                NavigationLink(value: WatchRoute.devices) {
                    Label(loc("Devices"), systemImage: "square.grid.2x2.fill")
                }
            }
        }
        .navigationDestination(for: WatchRoute.self) { route in
            switch route {
            case .alerts: CriticalAlertsScreen(store: store)
            case .devices: DevicesScreen(store: store)
            }
        }
        .navigationDestination(for: WatchDeviceSnapshot.self) { device in
            DeviceSnapshotScreen(device: device)
        }
        .navigationDestination(for: WidgetAlert.self) { alert in
            // Resolve the alert's device (joined by name) so the snapshot screen can show full device
            // detail; falls back to an alert-only view when the device isn't in the synced set.
            DeviceSnapshotScreen(device: store.snapshot.devices.first { $0.name == alert.deviceName }, alert: alert)
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

// MARK: - Active Alerts

struct CriticalAlertsScreen: View {
    let store: WatchStore

    var body: some View {
        let model = store.alertList
        Group {
            if model.isEmpty {
                ContentUnavailableView(loc("No active alerts"), systemImage: "checkmark.seal.fill")
            } else {
                List(model.alerts) { alert in
                    NavigationLink(value: alert) {
                        AlertRow(alert: alert)
                    }
                }
            }
        }
        .navigationTitle(loc("Alerts"))
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

// MARK: - Devices

struct DevicesScreen: View {
    let store: WatchStore

    var body: some View {
        let model = store.deviceList
        Group {
            if model.isEmpty {
                ContentUnavailableView(loc("No devices"), systemImage: "square.grid.2x2")
            } else {
                List(model.devices) { device in
                    NavigationLink(value: device) {
                        DeviceRow(device: device)
                    }
                }
            }
        }
        .navigationTitle(loc("Devices"))
    }
}

private struct DeviceRow: View {
    let device: WatchDeviceSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: device.status.watchSymbol)
                .foregroundStyle(device.status.watchTint)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)
                if let assetName = device.assetName {
                    Text(assetName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Device Snapshot

struct DeviceSnapshotScreen: View {
    let device: WatchDeviceSnapshot?
    var alert: WidgetAlert?

    var body: some View {
        List {
            header
            if let alert {
                Section(loc("Reason")) {
                    Text(alert.message).font(.body)
                }
            }
            if let device {
                detail(for: DeviceSnapshotViewModel(device))
            } else if let alert {
                Section {
                    LabeledContent(loc("Since"), value: alert.raisedAt, format: .relative(presentation: .named))
                }
            }
        }
        .navigationTitle(loc("Device"))
    }

    @ViewBuilder private var header: some View {
        let name = device?.name ?? alert?.deviceName ?? loc("Device")
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let assetName = device?.assetName {
                    Text(assetName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status = device?.status {
                    Label(status.watchLabel, systemImage: status.watchSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.watchTint)
                } else if let severity = alert?.severity {
                    Label(severity.watchLabel, systemImage: severity.watchSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(severity.watchTint)
                }
            }
        }
    }

    @ViewBuilder private func detail(for vm: DeviceSnapshotViewModel) -> some View {
        Section {
            if let battery = vm.batteryText {
                LabeledContent {
                    HStack(spacing: 4) {
                        if vm.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                        Text(battery)
                    }
                } label: {
                    Label(loc("Battery"), systemImage: "battery.100")
                }
            }
            LabeledContent {
                Text(vm.connectivityLabel)
            } label: {
                Label(loc("Connectivity"), systemImage: "antenna.radiowaves.left.and.right")
            }
            if let lastSeen = vm.lastSeenAt {
                LabeledContent(loc("Last seen"), value: lastSeen, format: .relative(presentation: .named))
            }
        }

        if vm.hasTelemetry {
            Section(loc("Telemetry")) {
                ForEach(vm.telemetry) { row in
                    LabeledContent(row.name, value: row.value)
                }
            }
        }
    }
}

// MARK: - Empty state

struct WatchEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label(loc("No fleet data"), systemImage: "iphone.gen3")
        } description: {
            Text(loc("Open SignalFlow on your iPhone to sync fleet status to your watch."))
        }
    }
}

// MARK: - Severity / status styling (watch-local, no DesignSystemKit dependency)

private extension AlertSeverity {
    var watchTint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
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

private extension DeviceStatus {
    var watchTint: Color {
        switch self {
        case .nominal: .green
        case .warning: .orange
        case .critical: .red
        case .offline: .secondary
        }
    }

    var watchSymbol: String {
        switch self {
        case .nominal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .offline: "wifi.slash"
        }
    }
}
