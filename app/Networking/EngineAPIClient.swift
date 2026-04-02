import Foundation

enum EngineAPIError: Error, LocalizedError {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)
    case apiError(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid engine base URL"
        case .badStatus(let c): "HTTP \(c)"
        case .decoding(let e): e.localizedDescription
        case .apiError(let c, let m): "\(c): \(m)"
        }
    }
}

/// Localhost API client; mutating POST uses Bearer token from Application Support.
struct EngineAPIClient: Sendable {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8756")!) {
        self.baseURL = baseURL
    }

    /// WebSocket URL for `GET /ws` (same host/port as REST, `ws` or `wss` scheme).
    var websocketURL: URL? {
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = (c.scheme == "https") ? "wss" : "ws"
        return c.url?.appendingPathComponent("ws")
    }

    private func token() -> String? {
        APITokenLoader.loadBearerToken()
    }

    func health() async throws -> HealthResponse {
        try await get(path: "health", decode: HealthResponse.self)
    }

    func stats() async throws -> StatsPayload {
        let env: ApiEnvelope<StatsPayload> = try await get(path: "stats", decode: ApiEnvelope<StatsPayload>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "stats failed")
        }
        return d
    }

    func queries(limit: Int = 50) async throws -> [DnsQueryItem] {
        var c = URLComponents(url: baseURL.appendingPathComponent("queries"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let env: ApiEnvelope<[DnsQueryItem]> = try await get(url: c.url!, decode: ApiEnvelope<[DnsQueryItem]>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "queries failed")
        }
        return d
    }

    func devices() async throws -> [DeviceDTO] {
        let env: ApiEnvelope<[DeviceDTO]> = try await get(path: "devices", decode: ApiEnvelope<[DeviceDTO]>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "devices failed")
        }
        return d
    }

    func alerts() async throws -> [AlertDTO] {
        let env: ApiEnvelope<[AlertDTO]> = try await get(path: "alerts", decode: ApiEnvelope<[AlertDTO]>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "alerts failed")
        }
        return d
    }

    func settings() async throws -> SettingsPayload {
        let env: ApiEnvelope<SettingsPayload> = try await get(path: "settings", decode: ApiEnvelope<SettingsPayload>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "settings failed")
        }
        return d
    }

    func patchUpstream(_ upstream: String) async throws {
        let body = DnsPatchBody(dns: DnsPatchInner(upstream: upstream))
        try await postJSON(method: "POST", url: baseURL.appendingPathComponent("settings", isDirectory: false), body: body)
    }

    func patchDeviceName(id: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = baseURL.appendingPathComponent("devices", isDirectory: false).appendingPathComponent(enc, isDirectory: false)
        try await postJSON(method: "PATCH", url: url, body: Body(name: name))
    }

    // MARK: - Low level

    private func get<T: Decodable>(path: String, decode: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        return try await get(url: url, decode: T.self)
    }

    private func get<T: Decodable>(url: URL, decode: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        guard (200 ..< 300).contains(http.statusCode) else { throw EngineAPIError.badStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EngineAPIError.decoding(error)
        }
    }

    private func postJSON<B: Encodable>(method: String = "POST", url: URL, body: B) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        guard (200 ..< 300).contains(http.statusCode) else { throw EngineAPIError.badStatus(http.statusCode) }
        if let env = try? JSONDecoder().decode(PostAckEnvelope.self, from: data), env.ok == false {
            throw EngineAPIError.apiError(env.error?.code ?? "error", env.error?.message ?? "request failed")
        }
    }
}

/// Decodes only `ok` + `error` so PATCH/POST responses with arbitrary `data` still parse.
private struct PostAckEnvelope: Decodable {
    let ok: Bool
    let error: ApiErrorBody?
}
