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

    private func heroBody(firing: Bool) -> some View {
        HStack(spacing: Spacing.lg) {
            IconBadge(firing ? "bell.badge.fill" : "checkmark.seal.fill", tint: firing ? .red : .green, size: 52)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if firing {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text("\(model.stats.activeAlerts)")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(.red)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(loc("Active alerts"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(loc("Requires attention"))
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
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Fleet health quantified: the gauge ring + its qualitative word. The proportion lives here (in the
    /// ring), so the status list below is plain counts — no duplicate bar.
    private var healthCard: some View {
        let band = model.stats.healthBand
        let percent = model.stats.healthFraction.formatted(.percent.precision(.fractionLength(0)))
        return CardSection(loc("Fleet health"), systemImage: "heart.text.square.fill") {
            HStack(spacing: Spacing.xl) {
                HealthGauge(fraction: model.stats.healthFraction, tint: band.tint)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(band.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(band.tint)
                    Text(loc("Based on \(model.stats.totalDevices) devices"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(band.label)
            .accessibilityValue(percent)
        }
    }

    /// The status mix as plain, scannable rows — a shape-and-colour status glyph (never colour alone),
    /// the localized status word, and the count.
    private var statusBreakdown: some View {
        CardSection(loc("Fleet status"), systemImage: "chart.bar.fill") {
            VStack(spacing: Spacing.md) {
                StatusBreakdownRow(status: .nominal, count: model.stats.nominal)
                StatusBreakdownRow(status: .warning, count: model.stats.warning)
                StatusBreakdownRow(status: .critical, count: model.stats.critical)
                StatusBreakdownRow(status: .offline, count: model.stats.offline)
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
                        EventListRow(kind: event.kind, deviceName: event.deviceName, occurredAt: event.occurredAt)
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

/// One status row: a shape-and-colour status glyph (so it reads without colour), the localized status
/// word, and the count.
private struct StatusBreakdownRow: View {
    let status: DeviceStatus
    let count: Int

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .font(.body)
                .frame(width: 24)
            Text(status.label)
            Spacer()
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
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
