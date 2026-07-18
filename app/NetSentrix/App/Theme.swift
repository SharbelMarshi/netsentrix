import AppKit
import SwiftUI

/// Semantic tokens mapped to system colors so every surface uses native
/// materials, follows the user's accent, and adapts to appearance changes.
/// Legacy names kept to avoid churn across screens.
enum Theme {
    static let deepNavy = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let allowed = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let blocked = Color(nsColor: .systemRed)
    static let infoMuted = Color(nsColor: .tertiaryLabelColor)
}
