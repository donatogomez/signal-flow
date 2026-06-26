import SwiftUI
import Charts
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
        // Two top-level glance pages reached with a horizontal swipe (the watchOS carousel idiom): the
        // fleet Overview and the Devices list. A *single* NavigationStack wraps the whole carousel, so
        // drilling into a device pushes the detail *over* both pages — from the detail you go back with the
        // chevron (you can't swipe to Overview), and only the Devices page itself swipes back to Overview.
        NavigationStack {
            TabView {
                FleetSummaryScreen(store: store)
                DevicesScreen(store: store)
            }
            .watchHorizontalPaging()
            .navigationDestination(for: WatchDeviceSnapshot.self) { device in
                DeviceSnapshotScreen(device: device)
            }
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
    }

    private var loaded: some View {
        let fleet = store.fleet
        return ScrollView {
            VStack(spacing: 12) {
                FleetRing(online: fleet.online, warning: fleet.warning, critical: fleet.critical, offline: fleet.offline)
                    .frame(height: 116)
                    .padding(.top, 2)

                HStack(spacing: 0) {
                    StatusPercent(value: fleet.online, total: fleet.total, tint: .green, label: loc("Healthy"))
                    Divider().frame(height: 28)
                    StatusPercent(value: fleet.warning, total: fleet.total, tint: .orange, label: loc("Caution"))
                    Divider().frame(height: 28)
                    StatusPercent(value: fleet.critical, total: fleet.total, tint: .red, label: loc("Critical"))
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// The compact fleet glance: a **closed** ring whose arcs are the fleet split by severity — healthy
/// (green), warning (orange), critical (red), offline (grey) — drawn clockwise from 12 o'clock, with the
/// healthy ratio + "En orden" at its centre (watchOS Activity-ring idiom).
private struct FleetRing: View {
    let online: Int
    let warning: Int
    let critical: Int
    let offline: Int
    private var total: Int { online + warning + critical + offline }

    /// Cumulative `[start, end]` fractions (0…1) per non-empty segment, in severity order.
    private var arcs: [(from: Double, to: Double, color: Color)] {
        guard total > 0 else { return [] }
        let t = Double(total)
        var acc = 0.0
        return [(online, Color.green), (warning, .orange), (critical, .red), (offline, .gray)]
            .filter { $0.0 > 0 }
            .map { count, color in
                let from = acc / t
                acc += Double(count)
                return (from, acc / t, color)
            }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 9))
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(verbatim: "\(online)/\(total)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(loc("Healthy"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc("\(online)/\(total) healthy"))
    }
}

/// One severity column below the ring: its share of the fleet as a tinted percentage over a small label
/// (the Option-3 "progress breakdown" idiom, without the bar).
private struct StatusPercent: View {
    let value: Int
    let total: Int
    let tint: Color
    let label: String
    private var percent: Int { total > 0 ? Int((Double(value) / Double(total) * 100).rounded()) : 0 }

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: "\(percent)%")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
                .listStyle(.plain)
            }
        }
        .navigationTitle(loc("Alerts"))
    }
}

private struct AlertRow: View {
    let alert: WidgetAlert

    var body: some View {
        HStack(spacing: 10) {
            // Inbox style: a filled severity-coloured circle leads each row.
            Image(systemName: alert.severity == .info ? "info.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(alert.severity.watchTint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert.deviceName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(alert.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(alert.raisedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption2)
                    .foregroundStyle(alert.severity.watchTint)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Devices

struct DevicesScreen: View {
    let store: WatchStore

    var body: some View {
        let model = store.deviceList
        // The most pressing alert per device (severity-then-recency, joined by name): its message becomes
        // the row subtitle ("Temperatura alta") and its age the trailing label. `alertList.alerts` is
        // already sorted most-relevant-first, so the first hit per device is the one to show.
        let alertsByDevice = Dictionary(store.alertList.alerts.map { ($0.deviceName, $0) },
                                        uniquingKeysWith: { first, _ in first })
        Group {
            if model.isEmpty {
                ContentUnavailableView(loc("No devices"), systemImage: "square.grid.2x2")
            } else {
                let devices = model.devices
                List {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        let alert = alertsByDevice[device.name]
                        VStack(spacing: 6) {
                            NavigationLink(value: device) {
                                DeviceRow(device: device, alert: alert, since: alert.map { store.firstSeen($0.id) })
                            }
                            if index < devices.count - 1 {
                                Divider() // inbox-style separator between rows
                            }
                        }
                        .listRowBackground(Color.clear) // flat black rows — the divider carries the structure
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

/// Inbox-style device row (mockup #8): a filled, status-coloured circle leads, then the device name over
/// **its problem** (the active-alert message), with the alert's age tinted on the trailing edge — the
/// same layout as a mail inbox.
private struct DeviceRow: View {
    let device: WatchDeviceSnapshot
    /// The device's most pressing active alert, if any — drives the subtitle (the problem) and the age.
    var alert: WidgetAlert?
    /// When that alert first appeared on this watch — the anchor for its real-time "2 min" age.
    var since: Date?

    /// A meaningful **one-to-two word** problem label ("Temperatura", "Batería baja") when there's an
    /// alert; otherwise the asset name, but only when it adds information (i.e. differs from the device
    /// name — avoids the redundant "Reefer 19 / Reefer 19").
    private var subtitle: String? {
        if let alert { return AlertText.shortLabel(alert.metric) }
        if let assetName = device.assetName, assetName != device.name { return assetName }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.status.watchRowSymbol)
                .font(.title2)
                .foregroundStyle(device.status.watchTint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8) // shrink rather than truncate "Batería baja" etc.
                    }
                }
                Spacer(minLength: 4)
                if let since {
                    // Bare elapsed age — "2 min", "3 h" — no "hace"/"ago" prefix (mockup #8).
                    Text(Duration.seconds(max(0, Date.now.timeIntervalSince(since)))
                        .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1)))
                        .font(.caption2)
                        .foregroundStyle(device.status.watchTint)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Device Detail (paged "Metrics + Trend")

/// A paged, metric-centric device screen: each page answers **one** question and is reached with a
/// **horizontal swipe** (and the Digital Crown), with a page indicator. No nested cards, no dense
/// scrolling — large type, lots of whitespace. Pushed *over* the top-level carousel, so the only way out
/// is the back chevron (a swipe never escapes to the Overview page).
///
/// Pages are built from the **already-synced** data: an Overview (which also carries connectivity +
/// battery), then one page per synced metric — the device's **primary metric** and, when the device
/// reports it, **humidity** — each with its value, trend delta and sparkline. Devices that report neither
/// extra metric simply have the two pages.
struct DeviceSnapshotScreen: View {
    let device: WatchDeviceSnapshot?
    var alert: WidgetAlert?

    var body: some View {
        TabView {
            overviewPage
            if let vm {
                ForEach(vm.metricPages) { metricPage($0) }
            }
        }
        .watchHorizontalPaging()
    }

    private var vm: DeviceSnapshotViewModel? { device.map(DeviceSnapshotViewModel.init) }

    // MARK: Page 1 — Overview

    private var overviewPage: some View {
        VStack(spacing: 6) {
            Image(systemName: severitySymbol)
                .font(.system(size: 30))
                .foregroundStyle(severityTint)
            Text(severityLabel)
                .font(.headline)
                .foregroundStyle(severityTint)
                .lineLimit(1)
            // The alert age lives on the list row now, so the detail stays focused on status + telemetry.
            if let vm {
                VStack(spacing: 6) {
                    Label(vm.connectivityLabel, systemImage: vm.connectivityState.watchSymbol)
                        .foregroundStyle(vm.connectivityState.watchTint)
                    if let batteryText = vm.batteryText {
                        Label(vm.isCharging ? "\(batteryText) ⚡︎" : batteryText,
                              systemImage: vm.battery?.level.watchSymbol ?? "battery.100percent")
                            .foregroundStyle(vm.battery?.level.watchTint ?? .secondary)
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: Metric pages (one per synced metric — primary, then humidity when present)

    private func metricPage(_ primary: DeviceSnapshotViewModel.PrimaryMetric) -> some View {
        VStack(spacing: 6) {
            Text(primary.name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(primary.value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let delta = primary.deltaText {
                Text(delta)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severityTint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if primary.hasTrend {
                MiniTrendChart(points: primary.history, tint: severityTint, height: 64)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(primary.name), \(primary.value)"))
    }

    private var severityTint: Color { alert?.severity.watchTint ?? device?.status.watchTint ?? .secondary }
    private var severitySymbol: String { alert?.severity.watchSymbol ?? device?.status.watchSymbol ?? "questionmark.circle" }
    private var severityLabel: String { alert?.severity.watchLabel ?? device?.status.watchLabel ?? loc("Device") }
}

private extension View {
    /// watchOS's horizontal page carousel (swipe / Digital Crown). `.page` is unavailable on the macOS
    /// host build (where this never renders), so it's a no-op there.
    @ViewBuilder func watchHorizontalPaging() -> some View {
        #if os(watchOS)
        tabViewStyle(.page)
        #else
        self
        #endif
    }
}

/// A small native sparkline of a metric's recent values — a line over a faint matching-tint fill, with
/// dots on each sample. No axes, no gradients; the trend delta text above carries the spoken meaning.
private struct MiniTrendChart: View {
    let points: [Double]
    let tint: Color
    var height: CGFloat = 44

    var body: some View {
        let lo = points.min() ?? 0
        let hi = points.max() ?? 1
        let pad = Swift.max((hi - lo) * 0.15, 0.0001)
        return Chart(Array(points.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("i", index), y: .value("v", value))
                .foregroundStyle(tint.opacity(0.18))
            LineMark(x: .value("i", index), y: .value("v", value))
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            PointMark(x: .value("i", index), y: .value("v", value))
                .foregroundStyle(tint)
                .symbolSize(14)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .frame(height: height)
        .accessibilityHidden(true)
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

    /// Filled, circular glyph for the inbox-style Devices rows (mockup #8) — uniform circles tinted by
    /// status, like ``AlertRow``'s severity dots.
    var watchRowSymbol: String {
        switch self {
        case .nominal: "checkmark.circle.fill"
        case .warning, .critical: "exclamationmark.circle.fill"
        case .offline: "slash.circle.fill"
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

private extension ConnectivityStatus.State {
    var watchTint: Color {
        switch self {
        case .online: .green
        case .degraded: .orange
        case .offline: .secondary
        }
    }

    var watchSymbol: String {
        switch self {
        case .online: "wifi"
        case .degraded: "wifi.exclamationmark"
        case .offline: "wifi.slash"
        }
    }
}

private extension BatteryStatus.Level {
    var watchTint: Color {
        switch self {
        case .critical: .red
        case .low: .orange
        case .nominal: .green
        }
    }

    var watchSymbol: String {
        switch self {
        case .critical: "battery.0percent"
        case .low: "battery.25percent"
        case .nominal: "battery.100percent"
        }
    }
}
