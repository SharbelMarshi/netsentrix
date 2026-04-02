import SwiftUI

/// Brand tokens — dark-first; expand per design spec.
enum Theme {
    static let deepNavy = Color(red: 11 / 255, green: 18 / 255, blue: 32 / 255)
    static let surface = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    /// Slightly lifted card surface vs `surface`.
    static let cardBackground = Color(red: 22 / 255, green: 30 / 255, blue: 48 / 255)
    static let cardStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    static let textPrimary = Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)
    static let textSecondary = Color(red: 156 / 255, green: 163 / 255, blue: 175 / 255)
    static let allowed = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    /// Muted amber for partial / warning (not saturated).
    static let warning = Color(red: 217 / 255, green: 150 / 255, blue: 72 / 255)
    static let blocked = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static let infoMuted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
}
