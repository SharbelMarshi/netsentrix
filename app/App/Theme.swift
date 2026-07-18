import AppKit
import SwiftUI

/// Brand tokens. Every token is a dynamic color (light / dark provider), so the
/// app follows the system appearance without per-view changes.
enum Theme {
    /// App background.
    static let deepNavy = adaptive(light: srgb(242, 245, 250), dark: srgb(11, 18, 32))
    static let surface = adaptive(light: srgb(248, 250, 252), dark: srgb(17, 24, 39))
    /// Slightly lifted card surface vs `surface`.
    static let cardBackground = adaptive(light: srgb(255, 255, 255), dark: srgb(22, 30, 48))
    static let cardStroke = adaptive(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let accent = adaptive(light: srgb(37, 99, 235), dark: srgb(59, 130, 246))
    static let textPrimary = adaptive(light: srgb(17, 24, 39), dark: srgb(229, 231, 235))
    static let textSecondary = adaptive(light: srgb(75, 85, 99), dark: srgb(156, 163, 175))
    static let allowed = adaptive(light: srgb(22, 163, 74), dark: srgb(34, 197, 94))
    /// Muted amber for partial / warning (not saturated).
    static let warning = adaptive(light: srgb(180, 83, 9), dark: srgb(217, 150, 72))
    static let blocked = adaptive(light: srgb(220, 38, 38), dark: srgb(239, 68, 68))
    static let infoMuted = adaptive(light: srgb(100, 116, 139), dark: srgb(148, 163, 184))

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}
