import Foundation

enum APITokenLoader {
    /// User-configurable token path (Settings → Engine connection).
    static let defaultsKey = "apiTokenFilePath"
    /// Where the embedded LaunchDaemon writes its token (see packaging/macos/app/com.netsentrix.engine.plist).
    static let daemonDefaultTokenPath = "/usr/local/var/netsentrix/NetSentrix/api.token"

    /// Resolution order: `NETSENTRIX_TOKEN_FILE` env → Settings override →
    /// `~/Library/Application Support/NetSentrix/api.token` → the embedded
    /// daemon's default path. Match the engine (`GET /health` → `api_token_file`).
    static func loadBearerToken() -> String? {
        if let raw = ProcessInfo.processInfo.environment["NETSENTRIX_TOKEN_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return readToken(from: URL(fileURLWithPath: raw))
        }
        if let raw = UserDefaults.standard.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return readToken(from: URL(fileURLWithPath: (raw as NSString).expandingTildeInPath))
        }
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent("NetSentrix", isDirectory: true).appendingPathComponent("api.token")
            if let token = readToken(from: url) {
                return token
            }
        }
        return readToken(from: URL(fileURLWithPath: daemonDefaultTokenPath))
    }

    private static func readToken(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else {
            return nil
        }
        return s
    }
}
