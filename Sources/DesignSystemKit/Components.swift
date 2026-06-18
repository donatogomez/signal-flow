import SwiftUI
import DomainKit

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
            Label("\(Int(battery.percentage))%", systemImage: battery.symbol)
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
        .padding(Spacing.lg)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
        .padding(Spacing.lg)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .frame(width: 24)
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

/// A neutral empty-state placeholder.
public struct EmptyHint: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.md)
    }
}
