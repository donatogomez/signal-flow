import SwiftUI

public extension Color {
    /// SignalFlow's restrained brand accent — a calm indigo, deliberately distinct from the semantic
    /// status/severity hues (green / orange / red / blue) so it only ever reads as interactive chrome
    /// (selection, links, controls, the fleet's leading glyph), never as a status. Light-appearance only.
    static let signalFlowAccent = Color(.sRGB, red: 0.35, green: 0.34, blue: 0.80, opacity: 1)
}

public extension View {
    /// The premium grouped-card surface used by every SignalFlow card and tile: a subtle fill, a 0.5pt
    /// hairline for definition on white, and a whisper shadow for gentle elevation. No materials, no
    /// gradients — just the Apple grouped-card look. Centralized so the whole app stays consistent.
    func cardSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(.quaternary))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
