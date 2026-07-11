import SwiftUI
import DomainKit
import DesignSystemKit

/// The monitoring home: headline figures, a fleet status breakdown, and a recent-events feed.
/// Information-dense and calm — modeled on Apple's Weather/Home summary surfaces.
public struct DashboardScreen: View {
    @State private var model: DashboardModel
    /// Routes the active-alerts hero to the Alerts tab (wired by the app root to its tab selection).
    private let onShowAlerts: () -> Void

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        events: any EventRepository,
        onShowAlerts: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: DashboardModel(assets: assets, devices: devices, alerts: alerts, events: events))
        self.onShowAlerts = onShowAlerts
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .failed(let message):
                    errorState(message)
                case .loading:
                    content(placeholder: true)
                        .redacted(reason: .placeholder)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(loc("Loading dashboard"))
                case .loaded:
                    content(placeholder: false)
                }
            }
            .padding(Spacing.lg)
            .animation(.default, value: model.phase)
        }
        .background(Color.signalFlowGroupedBackground.ignoresSafeArea())
        .navigationTitle(loc("Overview"))
        .task { await model.observe() }
    }

    @ViewBuilder
    private func content(placeholder: Bool) -> some View {
        hero
        healthCard
        statusBreakdown
        recentActivity(placeholder: placeholder)
    }

    /// The one-second verdict — "do I need to worry right now?". When alerts are firing it's a loud,
    /// **tappable** red card that doubles as the entry point to the Alerts tab; when the fleet is clear it's
    /// a calm green reassurance. Leads the screen and outweighs everything below.
    @ViewBuilder
    private var hero: some View {
        if model.stats.activeAlerts > 0 {
            Button(action: onShowAlerts) { heroBody(firing: true) }
                .buttonStyle(.plain)
                .accessibilityHint(loc("Opens Alerts"))
        } else {
            heroBody(firing: false)
        }
    }

    /// Hero metric scale: the count dominates like an Apple Health metric, scaling with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroCountSize: CGFloat = 48

    private func heroBody(firing: Bool) -> some View {
        // Wallet/Home-card proportions: a large icon anchor, the count as the dominant element, generous
        // padding, and everything optically centred on the card's vertical axis.
        HStack(alignment: .center, spacing: Spacing.xl) {
            IconBadge(firing ? "bell.badge.fill" : "checkmark.seal.fill", tint: firing ? .red : .green, size: 64)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if firing {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("\(model.stats.activeAlerts)")
                            .font(.system(size: heroCountSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(loc("Active alerts"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(loc("Requires immediate attention"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(loc("All systems nominal"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(loc("No active alerts"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.sm)
            if firing {
                // Standard iOS disclosure weight — visible, never competing with the count.
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xl)
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// SignalFlow's signature Fleet Health indicator: the branded semicircular gauge carries the verdict
    /// and the operational count ("5 / 10"); the caption grounds it. No bare percentage — the word is the
    /// message.
    private var healthCard: some View {
        let band = model.stats.healthBand
        let detail = loc("\(model.stats.nominal) / \(model.stats.totalDevices) operational")
        return CardSection(loc("Fleet health"), systemImage: "heart.text.square.fill") {
            VStack(spacing: Spacing.md) {
                HealthGauge(fraction: model.stats.healthFraction, tint: band.tint, verdict: band.label, detail: detail)
                    .padding(.horizontal, Spacing.sm)
                Text(loc("Based on the current state of all devices."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(loc("Fleet health"))
            .accessibilityValue("\(band.label), \(detail)")
        }
    }

    /// The status mix as four compact columns — a shape-and-colour status glyph (never colour alone), the
    /// count, and the localized word. The gauge already communicates overall health, so no bar here.
    private var statusBreakdown: some View {
        CardSection(loc("Fleet status"), systemImage: "chart.bar.fill") {
            HStack(spacing: 0) {
                StatusColumn(status: .nominal, count: model.stats.nominal)
                Divider().frame(height: 44)
                StatusColumn(status: .warning, count: model.stats.warning)
                Divider().frame(height: 44)
                StatusColumn(status: .critical, count: model.stats.critical)
                Divider().frame(height: 44)
                StatusColumn(status: .offline, count: model.stats.offline)
            }
        }
    }

    private func recentActivity(placeholder: Bool) -> some View {
        CardSection(loc("Recent events"), systemImage: "clock.arrow.circlepath") {
            if placeholder {
                // Skeleton rows; redaction greys them while the first load is in flight.
                VStack(spacing: Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        EventListRow(kind: .connected, occurredAt: .now)
                    }
                }
            } else if model.recentEvents.isEmpty {
                EmptyHint(loc("No events yet"), systemImage: "tray")
            } else {
                // Compact operational feed — the few most recent changes, not a full log.
                VStack(spacing: Spacing.md) {
                    ForEach(model.recentEvents.prefix(4)) { event in
                        EventListRow(kind: event.kind, deviceName: event.deviceName, occurredAt: model.firstSeen(event: event.id))
                    }
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView(
            loc("Couldn't load the dashboard"),
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// One status column: a shape-and-colour status glyph (so it reads without colour) over the count and the
/// localized word. Four of these read as a compact, scannable status strip.
private struct StatusColumn: View {
    let status: DeviceStatus
    let count: Int

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: status.symbol)
                .font(.title3)
                .foregroundStyle(status.tint)
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(status.tint)
                .monospacedDigit()
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(status.label))
        .accessibilityValue(Text("\(count)"))
    }
}

/// Maps the qualitative health band to a semantic colour and a localized word for the gauge.
private extension HealthBand {
    var tint: Color {
        switch self {
        case .excellent, .good: .green
        case .attention: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }

    var label: String {
        switch self {
        case .excellent: loc("Excellent")
        case .good: loc("Healthy")
        case .attention: loc("At risk")
        case .critical: loc("Critical")
        case .unknown: loc("No data")
        }
    }
}
