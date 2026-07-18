import Foundation

enum EngineAPIError: Error, LocalizedError {
    case invalidURL
    case badStatus(Int)
    case unauthorized
    case decoding(Error)
    case apiError(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid engine base URL"
        case .badStatus(let c): "HTTP \(c)"
        case .unauthorized:
            "Unauthorized — check that the app can read the same api.token file the engine uses (see Setup → Advanced or NETSENTRIX_TOKEN_FILE)."
        case .decoding(let e): e.localizedDescription
        case .apiError(let c, let m): "\(c): \(m)"
        }
    }
}

/// Localhost API client; mutating POST uses Bearer token from Application Support.
struct EngineAPIClient: Sendable {
    /// Fixed URL for tests; nil follows the user-configurable endpoint.
    private let overrideBaseURL: URL?

    var baseURL: URL {
        overrideBaseURL ?? EngineEndpoint.current
    }

    init(baseURL: URL? = nil) {
        self.overrideBaseURL = baseURL
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

    func queries(limit: Int = 50, deviceId: String? = nil) async throws -> [DnsQueryItem] {
        var c = URLComponents(url: baseURL.appendingPathComponent("queries"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let deviceId, !deviceId.isEmpty {
            items.append(URLQueryItem(name: "device_id", value: deviceId))
        }
        c.queryItems = items
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

    func device(id: String) async throws -> DeviceDTO {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = baseURL.appendingPathComponent("devices", isDirectory: false).appendingPathComponent(enc, isDirectory: false)
        let env: ApiEnvelope<DeviceDTO> = try await get(url: url, decode: ApiEnvelope<DeviceDTO>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "device failed")
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

    /// `GET /insights/daily` — bounded aggregates (no auth).
    func insightsDaily(hours: UInt32? = nil) async throws -> InsightsDailyDTO {
        var c = URLComponents(url: baseURL.appendingPathComponent("insights/daily"), resolvingAgainstBaseURL: false)!
        if let h = hours {
            c.queryItems = [URLQueryItem(name: "hours", value: String(h))]
        }
        guard let url = c.url else { throw EngineAPIError.invalidURL }
        let env: ApiEnvelope<InsightsDailyDTO> = try await get(url: url, decode: ApiEnvelope<InsightsDailyDTO>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "insights failed")
        }
        return d
    }

    /// `GET /queries/export.csv` — Bearer required.
    func exportQueriesCSV(hours: UInt32 = 24, limit: UInt32 = 10_000) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent("queries/export.csv"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "hours", value: String(hours)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = c.url else { throw EngineAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        if let t = token() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        if http.statusCode == 401 { throw EngineAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else { throw EngineAPIError.badStatus(http.statusCode) }
        return data
    }

    /// `POST /feedback/domain` — user “safe” / “suspicious” verdicts merged into the classifier.
    func postDomainFeedback(pattern: String, verdict: String) async throws {
        struct B: Encodable {
            let pattern: String
            let verdict: String
        }
        let url = baseURL.appendingPathComponent("feedback/domain", isDirectory: false)
        try await postJSON(url: url, body: B(pattern: pattern, verdict: verdict))
    }

    func settings() async throws -> SettingsPayload {
        let env: ApiEnvelope<SettingsPayload> = try await get(path: "settings", decode: ApiEnvelope<SettingsPayload>.self)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "settings failed")
        }
        return d
    }

    /// POST `/settings` — only non-nil fields are sent; engine merges into config.
    func postSettings(dns: SettingsDnsPatch) async throws -> SettingsPayload {
        let body = SettingsPostBody(dns: dns)
        let url = baseURL.appendingPathComponent("settings", isDirectory: false)
        return try await postJSONReturningEnvelope(url: url, body: body)
    }

    /// Reread `config.toml` from disk and reload lists/filter (manual edits outside the app).
    func postReload() async throws {
        try await postJSONExpectOk(url: baseURL.appendingPathComponent("reload", isDirectory: false), body: EmptyJSON())
    }

    /// Idempotent: DNS answers **SERVFAIL** and does not forward while paused.
    func postDnsPause() async throws {
        try await postJSONExpectOk(url: baseURL.appendingPathComponent("dns/pause", isDirectory: false), body: EmptyJSON())
    }

    func postDnsResume() async throws {
        try await postJSONExpectOk(url: baseURL.appendingPathComponent("dns/resume", isDirectory: false), body: EmptyJSON())
    }

    func patchDevice(id: String, name: String? = nil, dnsPolicy: String? = nil, tags: String? = nil) async throws {
        struct Body: Encodable {
            var name: String?
            var dnsPolicy: String?
            var tags: String?
            enum CodingKeys: String, CodingKey {
                case name
                case dnsPolicy = "dns_policy"
                case tags
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(name, forKey: .name)
                try c.encodeIfPresent(dnsPolicy, forKey: .dnsPolicy)
                try c.encodeIfPresent(tags, forKey: .tags)
            }
        }
        guard name != nil || dnsPolicy != nil || tags != nil else { return }
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = baseURL.appendingPathComponent("devices", isDirectory: false).appendingPathComponent(enc, isDirectory: false)
        try await postJSON(method: "PATCH", url: url, body: Body(name: name, dnsPolicy: dnsPolicy, tags: tags))
    }

    /// POST `/block` — inserts `dns_block` rule and reloads the in-memory filter.
    func postBlockDomain(pattern: String) async throws {
        let url = baseURL.appendingPathComponent("block", isDirectory: false)
        try await postJSON(url: url, body: PatternPostBody(pattern: pattern))
    }

    /// POST `/allow` — inserts `dns_allow` rule and reloads the in-memory filter.
    func postAllowDomain(pattern: String) async throws {
        let url = baseURL.appendingPathComponent("allow", isDirectory: false)
        try await postJSON(url: url, body: PatternPostBody(pattern: pattern))
    }

    /// `GET /policy/time-overrides` — Bearer required.
    func timeOverrides() async throws -> [TimeOverrideDTO] {
        let env: ApiEnvelope<[TimeOverrideDTO]> = try await get(
            path: "policy/time-overrides",
            decode: ApiEnvelope<[TimeOverrideDTO]>.self
        )
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "time overrides failed")
        }
        return d
    }

    /// `POST /policy/time-overrides` — minutes are 0–1439 (local time-of-day; overnight when start > end).
    func postTimeOverride(scopeDeviceId: String?, startMin: Int, endMin: Int, dnsPolicy: String) async throws {
        struct Body: Encodable {
            let scopeDeviceId: String?
            let startMin: Int
            let endMin: Int
            let dnsPolicy: String
            enum CodingKeys: String, CodingKey {
                case scopeDeviceId = "scope_device_id"
                case startMin = "start_min"
                case endMin = "end_min"
                case dnsPolicy = "dns_policy"
            }
        }
        let url = baseURL.appendingPathComponent("policy/time-overrides", isDirectory: false)
        try await postJSON(
            url: url,
            body: Body(scopeDeviceId: scopeDeviceId, startMin: startMin, endMin: endMin, dnsPolicy: dnsPolicy)
        )
    }

    func deleteTimeOverride(id: Int64) async throws {
        let url = baseURL
            .appendingPathComponent("policy/time-overrides", isDirectory: false)
            .appendingPathComponent(String(id), isDirectory: false)
        try await postJSON(method: "DELETE", url: url, body: EmptyJSON())
    }

    // MARK: - Low level

    private struct PatternPostBody: Encodable {
        let pattern: String
    }

    private func get<T: Decodable>(path: String, decode: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        return try await get(url: url, decode: T.self)
    }

    private func get<T: Decodable>(url: URL, decode: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if let t = token() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        if http.statusCode == 401 { throw EngineAPIError.unauthorized }
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
        if http.statusCode == 401 { throw EngineAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw postFailureError(data: data, statusCode: http.statusCode)
        }
        if let env = try? JSONDecoder().decode(PostAckEnvelope.self, from: data), env.ok == false {
            throw EngineAPIError.apiError(env.error?.code ?? "error", env.error?.message ?? "request failed")
        }
    }

    /// Prefer engine `error.code` / `error.message` when the response body is JSON.
    private func postFailureError(data: Data, statusCode: Int) -> Error {
        struct FailEnv: Decodable {
            let error: ApiErrorBody?
        }
        if let env = try? JSONDecoder().decode(FailEnv.self, from: data), let e = env.error {
            return EngineAPIError.apiError(e.code, e.message)
        }
        return EngineAPIError.badStatus(statusCode)
    }

    private func postJSONReturningEnvelope<B: Encodable>(url: URL, body: B) async throws -> SettingsPayload {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        if http.statusCode == 401 { throw EngineAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw postFailureError(data: data, statusCode: http.statusCode)
        }
        let env = try JSONDecoder().decode(ApiEnvelope<SettingsPayload>.self, from: data)
        guard env.ok, let d = env.data else {
            throw EngineAPIError.apiError(env.error?.code ?? "unknown", env.error?.message ?? "settings save failed")
        }
        return d
    }

    private func postJSONExpectOk<B: Encodable>(url: URL, body: B) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EngineAPIError.badStatus(-1) }
        if http.statusCode == 401 { throw EngineAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw postFailureError(data: data, statusCode: http.statusCode)
        }
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
