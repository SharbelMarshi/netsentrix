import Foundation

enum DomainPattern {
    /// Normalizes user input for `POST /block` / `POST /allow`: trims whitespace,
    /// lowercases, and strips trailing dots. Returns "" for unusable input.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
