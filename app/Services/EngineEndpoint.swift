import Foundation

/// User-configurable engine API address (Settings → Engine connection).
/// REST calls read it per-request and the WebSocket supervisor per-connect,
/// so changes apply without relaunching.
enum EngineEndpoint {
    static let defaultsKey = "engineBaseURL"
    static let fallback = URL(string: "http://127.0.0.1:8756")!

    static var current: URL {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let url = normalize(raw)
        else {
            return fallback
        }
        return url
    }

    /// Accepts "127.0.0.1:8756", "http://127.0.0.1:8756", or a bare host.
    /// Returns nil for unusable input.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme, url.host != nil,
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    /// Persists the address; empty input restores the default.
    static func save(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || normalize(trimmed)?.absoluteString == fallback.absoluteString {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        }
    }
}
