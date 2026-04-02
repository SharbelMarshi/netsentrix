import Foundation

enum APITokenLoader {
    /// Default: `~/Library/Application Support/NetSentrix/api.token` (same layout as the engine’s default data dir for a normal user).
    /// For a root LaunchDaemon + shared token, set **`NETSENTRIX_TOKEN_FILE`** to the engine’s absolute path (match the plist / `GET /health` `api_token_file`).
    static func loadBearerToken() -> String? {
        if let raw = ProcessInfo.processInfo.environment["NETSENTRIX_TOKEN_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            return readToken(from: url)
        }
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = dir.appendingPathComponent("NetSentrix", isDirectory: true).appendingPathComponent("api.token")
        return readToken(from: url)
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
