import SwiftUI

public extension Color {
    /// SignalFlow's restrained brand accent — a calm indigo, deliberately distinct from the semantic
    /// status/severity hues (green / orange / red / blue) so it only ever reads as interactive chrome
    /// (selection, links, controls), never as a status.
    ///
    /// **Appearance-adaptive:** a deeper indigo in light, brightened in dark so it stays legible against
    /// the dark monitoring surfaces (the default appearance). On non-UIKit hosts (the macOS test build)
    /// it falls back to the light value.
    static let signalFlowAccent: Color = {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.55, green: 0.54, blue: 0.98, alpha: 1)
                : UIColor(red: 0.35, green: 0.34, blue: 0.80, alpha: 1)
        })
        #else
        return Color(.sRGB, red: 0.35, green: 0.34, blue: 0.80, opacity: 1)
        #endif
    }()
}

public extension Color {
    /// The page canvas behind grouped cards — light grey in Light, near-black in Dark (the system
    /// grouped background). Cards sit on this; ``cardSurface()`` raises above it.
    static let signalFlowGroupedBackground: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(white: 0.95)
        #endif
    }()

    /// The card fill — white in Light, an elevated dark grey in Dark — so cards read as raised above the
    /// grouped background, matching Apple's grouped-list surfaces.
    static let signalFlowCardFill: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(white: 1.0)
        #endif
    }()
}

public extension View {
    /// The premium grouped-card surface used by every SignalFlow card and tile: a raised white (Light) /
    /// elevated-grey (Dark) fill, a 0.5pt hairline for definition, and a whisper shadow for gentle
    /// elevation on the grouped background. No materials, no gradients — just the Apple grouped-card look.
    func cardSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color.signalFlowCardFill))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    /// Apple's grouped-list look — inset rounded cards on the grouped background — on iOS; plain on the
    /// macOS host build (where feature views never render), since `.insetGrouped` is iOS-only.
    @ViewBuilder func signalFlowGroupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.plain)
        #endif
    }
}
