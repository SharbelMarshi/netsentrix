import Foundation

enum APITokenLoader {
    /// Same path the engine uses: Application Support/NetSentrix/api.token
    static func loadBearerToken() -> String? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = dir.appendingPathComponent("NetSentrix", isDirectory: true).appendingPathComponent("api.token")
        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else {
            return nil
        }
        return s
    }
}
