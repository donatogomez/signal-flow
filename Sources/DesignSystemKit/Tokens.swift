import SwiftUI

/// Spacing scale used across SignalFlow surfaces. A small, fixed set keeps rhythm consistent.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    /// Internal padding for cards and tiles — slightly more generous than `lg` for a premium,
    /// less-cramped feel without making dense screens feel sparse.
    public static let cardPadding: CGFloat = 20
}

/// Corner radii for cards, chips, and tinted icon containers.
public enum Radius {
    public static let chip: CGFloat = 8
    public static let icon: CGFloat = 8
    public static let card: CGFloat = 16
}
