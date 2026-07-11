import SwiftUI
import Charts
import DomainKit

// MARK: - Sparkline

/// A tiny, axis-free trend line for digest cards (Health-Trends style): a line over a faint matching-tint
/// fill, no labels or gridlines, so it reads as a glanceable shape rather than a chart. Decorative — the
/// caller's surrounding text carries the meaning, so it's hidden from VoiceOver.
public struct Sparkline: View {
    private let points: [Double]
    private let tint: Color
    private let height: CGFloat

    public init(points: [Double], tint: Color, height: CGFloat = 44) {
        self.points = points
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { index, value in
            // Empty axis labels — the chart is decorative with hidden axes, so these must not become
            // (untranslated) localization catalog keys.
            AreaMark(x: .value("", index), y: .value("", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint.opacity(0.12))
            LineMark(x: .value("", index), y: .value("", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Status & severity badges

/// A compact, color-coded device status pill (icon + label).
public struct StatusBadge: View {
    private let status: DeviceStatus
    public init(_ status: DeviceStatus) { self.status = status }

    public var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.tint)
            .labelStyle(.titleAndIcon)
    }
}

/// A small severity chip used in alert rows.
public struct SeverityTag: View {
    private let severity: AlertSeverity
    public init(_ severity: AlertSeverity) { self.severity = severity }

    public var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(severity.tint)
            .background(severity.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}

/// A connectivity indicator (icon + label), color-coded.
public struct ConnectivityLabel: View {
    private let state: ConnectivityStatus.State
    public init(_ state: ConnectivityStatus.State) { self.state = state }

    public var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.caption)
            .foregroundStyle(state.tint)
    }
}

/// A battery indicator (icon + percentage), color-coded by charge level. Renders neutrally if unknown.
public struct BatteryLabel: View {
    private let battery: BatteryStatus?
    public init(_ battery: BatteryStatus?) { self.battery = battery }

    public var body: some View {
        if let battery {
            Label("\(Int(battery.percentage.rounded()))%", systemImage: battery.symbol)
                .font(.caption)
                .foregroundStyle(battery.tint)
                .monospacedDigit()
        } else {
            Label("—", systemImage: "battery.0percent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Leading icon

/// A tinted, rounded-square SF Symbol container for list/row leading glyphs — the Apple "settings row"
/// treatment. Lifts a bare glyph into a deliberate, scannable icon without adding decoration.
public struct IconBadge: View {
    private let systemImage: String
    private let tint: Color
    private let size: CGFloat

    public init(_ systemImage: String, tint: Color = .accentColor, size: CGFloat = 30) {
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            // Radius scales with the badge (≈ Radius.icon at row size) so large hero badges keep the
            // squircle proportions instead of reading boxy.
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Containers & rows

/// A titled card section with a subtle filled background — the building block for the dashboard and
/// detail surfaces.
public struct CardSection<Content: View>: View {
    private let title: String
    private let systemImage: String?
    private let content: Content

    public init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            } else {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
    }
}

/// A single statistic tile (large value + caption), used in the dashboard grid.
public struct StatTile: View {
    private let title: String
    private let value: String
    private let systemImage: String
    private let tint: Color

    public init(title: String, value: String, systemImage: String, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

/// A label/value row used in detail lists.
public struct KeyValueRow: View {
    private let label: String
    private let value: String
    private let systemImage: String?

    public init(_ label: String, value: String, systemImage: String? = nil) {
        self.label = label
        self.value = value
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack {
            if let systemImage {
                Label(label, systemImage: systemImage).foregroundStyle(.secondary)
            } else {
                Text(label).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// A recent-event row (icon + title + device + relative time), shared by the dashboard and detail
/// surfaces so the events feed looks identical everywhere.
public struct EventListRow: View {
    private let kind: DeviceEvent.Kind
    private let deviceName: String?
    private let occurredAt: Date

    public init(kind: DeviceEvent.Kind, deviceName: String? = nil, occurredAt: Date) {
        self.kind = kind
        self.deviceName = deviceName
        self.occurredAt = occurredAt
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(kind.symbol, tint: kind.tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(kind.title).font(.subheadline.weight(.medium))
                if let deviceName {
                    Text(deviceName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(occurredAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Health gauge

/// SignalFlow's signature **Fleet Health** indicator: a large semicircular gauge whose arc is banded by
/// semantic zones (crítico → riesgo → saludable, red → orange → green — colour *segments*, never a
/// gradient), a marker at the current health position, and a centred pulse motif over the **verdict** and
/// **operational count**. The verdict is the message; the count ("5 / 10") is the substance — no bare
/// percentage. Appearance-adaptive, Reduce-Motion friendly. Decorative internals are hidden; the caller
/// composes the spoken element (verdict + detail carry meaning).
public struct HealthGauge: View {
    private let fraction: Double
    private let tint: Color
    private let verdict: String
    private let detail: String
    private let lineWidth: CGFloat

    public init(fraction: Double, tint: Color, verdict: String, detail: String, lineWidth: CGFloat = 18) {
        self.fraction = fraction
        self.tint = tint
        self.verdict = verdict
        self.detail = detail
        self.lineWidth = lineWidth
    }

    private var clamped: Double { min(max(fraction, 0), 1) }

    /// Health-range → colour zones, drawn along the top semicircle (`trim` 0.5…1.0 = 9→12→3 o'clock).
    private static let zones: [(start: Double, end: Double, color: Color)] = [
        (0.0, 0.4, .red), (0.4, 0.75, .orange), (0.75, 1.0, .green)
    ]

    private func arcTrim(_ health: Double) -> Double { 0.5 + 0.5 * health }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                // Faint full track, then the semantic zones on top of it.
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, zone in
                    Circle()
                        .trim(from: arcTrim(zone.start), to: arcTrim(zone.end))
                        .stroke(zone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
                // Marker at the current health position — a round cap that reads as a dot, ringed in the
                // card fill so it lifts off the arc.
                Circle()
                    .trim(from: arcTrim(clamped) - 0.0001, to: arcTrim(clamped) + 0.0001)
                    .stroke(Color.signalFlowCardFill, style: StrokeStyle(lineWidth: lineWidth + 10, lineCap: .round))
                Circle()
                    .trim(from: arcTrim(clamped) - 0.0001, to: arcTrim(clamped) + 0.0001)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round))
                    .animation(.snappy, value: clamped)

                // Centre: pulse motif over the verdict + operational count.
                VStack(spacing: Spacing.xxs) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(verdict)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .offset(y: -w * 0.16)
            }
            .frame(width: w, height: w)
            .position(x: w / 2, y: geo.size.height)
        }
        .aspectRatio(1.9, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Filter chips

/// A horizontal, single-select row of filter chips — the visible, Dynamic-Type-friendly alternative to a
/// filter buried in a menu. The selected chip fills with its tint and bolds; each chip can carry an SF
/// Symbol tinted by its semantic colour, so status reads by shape **and** colour, never colour alone.
/// Chips expose their selected state to VoiceOver.
public struct FilterChips<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option
    private let label: (Option) -> String
    private let symbol: (Option) -> String?
    private let tint: (Option) -> Color

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String,
        symbol: @escaping (Option) -> String? = { _ in nil },
        tint: @escaping (Option) -> Color = { _ in .accentColor }
    ) {
        self.options = options
        self._selection = selection
        self.label = label
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(options, id: \.self) { option in
                    chip(option, selected: option == selection)
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func chip(_ option: Option, selected: Bool) -> some View {
        let tintColor = tint(option)
        return Button {
            selection = option
        } label: {
            HStack(spacing: Spacing.xs) {
                if let symbol = symbol(option) {
                    Image(systemName: symbol)
                        .foregroundStyle(tintColor)
                        .accessibilityHidden(true)
                }
                Text(label(option))
                    .foregroundStyle(selected ? tintColor : Color.primary)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(tintColor.opacity(0.16)) : AnyShapeStyle(.quaternary))
            )
            .overlay(
                Capsule().strokeBorder(selected ? tintColor.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Metric hero

/// A Stocks/Health-style hero for one metric: the metric name, a large dominant value, and an optional
/// change caption with a direction glyph. Typographic only — no chrome — so a screen drops it at the top
/// of a card. The value scales with Dynamic Type (`.largeTitle`). One combined accessibility element.
public struct MetricHeroValue: View {
    private let title: String
    private let value: String
    private let caption: String?
    private let captionSymbol: String?

    public init(title: String, value: String, caption: String? = nil, captionSymbol: String? = nil) {
        self.title = title
        self.value = value
        self.caption = caption
        self.captionSymbol = captionSymbol
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                if let captionSymbol {
                    Label(caption, systemImage: captionSymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(caption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A neutral, in-card empty-state placeholder. A compact, centered icon-over-text layout that mirrors
/// the system `ContentUnavailableView` language (used for full-screen empties), so empty states read
/// consistently whether they're a whole screen or a single card section.
public struct EmptyHint: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
