import Foundation

/// Setup / misconfiguration hint from `GET /health` → `setup_hints`.
struct SetupHintDTO: Codable, Sendable, Identifiable {
    var id: String { code }
    let code: String
    let severity: String
    let title: String
    let detail: String
    let suggestedFix: String?

    enum CodingKeys: String, CodingKey {
        case code, severity, title, detail
        case suggestedFix = "suggested_fix"
    }
}

/// Engine-computed protection summary (`GET /health` → `protection`).
struct ProtectionSummaryDTO: Codable, Sendable {
    let state: String
    let reasons: [String]
    let windowSeconds: UInt64
    let distinctClientsInWindow: Int64
    /// Non-loopback LAN client rows in the sliding window (volume).
    let lanQueryCountInWindow: Int64?
    /// Latest `dns_queries` time from non-loopback LAN clients only.
    let lastQueryMs: Int64?
    let lanCapable: Bool
    let dnsListen: String

    enum CodingKeys: String, CodingKey {
        case state, reasons
        case windowSeconds = "window_seconds"
        case distinctClientsInWindow = "distinct_clients_in_window"
        case lanQueryCountInWindow = "lan_query_count_in_window"
        case lastQueryMs = "last_query_ms"
        case lanCapable = "lan_capable"
        case dnsListen = "dns_listen"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        reasons = try c.decode([String].self, forKey: .reasons)
        windowSeconds = try c.decode(UInt64.self, forKey: .windowSeconds)
        distinctClientsInWindow = try c.decode(Int64.self, forKey: .distinctClientsInWindow)
        lanQueryCountInWindow = try c.decodeIfPresent(Int64.self, forKey: .lanQueryCountInWindow)
        lastQueryMs = try c.decodeIfPresent(Int64.self, forKey: .lastQueryMs)
        lanCapable = try c.decode(Bool.self, forKey: .lanCapable)
        dnsListen = try c.decode(String.self, forKey: .dnsListen)
    }
}

/// Mirrors engine `GET /health` JSON.
struct HealthResponse: Codable, Sendable {
    let ok: Bool
    let version: String
    let engine: String
    let apiListen: String
    let dnsListen: String
    /// Legacy: UDP listener; same meaning as `dns_udp_bound` when present.
    let dnsBound: Bool
    /// Nil on older engines — treat as `dnsBound`.
    let dnsUdpBound: Bool?
    /// Nil on older engines — unknown; do not infer TCP failure.
    let dnsTcpBound: Bool?
    let dnsLastError: String?
    let dnsTcpLastError: String?
    let engineStatus: String
    let suggestedLanIp: String?
    let snifferEnabled: Bool?
    let alertsTotal: Int64?
    let apiTokenFile: String?
    /// Resolved engine config file (same as startup).
    let configPath: String?
    /// Directory containing `api.token` / default DB layout (`.../NetSentrix`).
    let netsentrixDataDir: String?
    /// Active SQLite path from config.
    let dbPath: String?
    /// Newest **LAN** `dns_queries` timestamp (non-loopback `device_id` only), if any.
    let lastClientQueryMs: Int64?
    /// True when a LAN client query fell within `protection.window_seconds` (not localhost-only tests).
    let recentClientActivity: Bool?
    /// DNS answering paused (SERVFAIL); `POST /dns/pause` / `POST /dns/resume` or toggle `POST /pause`.
    let dnsPaused: Bool?
    /// Authoritative protection state from the engine; nil if talking to an older engine.
    let protection: ProtectionSummaryDTO?
    /// Actionable setup guidance; empty or absent on older engines.
    let setupHints: [SetupHintDTO]?

    enum CodingKeys: String, CodingKey {
        case ok, version, engine
        case apiListen = "api_listen"
        case dnsListen = "dns_listen"
        case dnsBound = "dns_bound"
        case dnsUdpBound = "dns_udp_bound"
        case dnsTcpBound = "dns_tcp_bound"
        case dnsLastError = "dns_last_error"
        case dnsTcpLastError = "dns_tcp_last_error"
        case engineStatus = "engine_status"
        case suggestedLanIp = "suggested_lan_ip"
        case snifferEnabled = "sniffer_enabled"
        case alertsTotal = "alerts_total"
        case apiTokenFile = "api_token_file"
        case configPath = "config_path"
        case netsentrixDataDir = "netsentrix_data_dir"
        case dbPath = "db_path"
        case lastClientQueryMs = "last_client_query_ms"
        case recentClientActivity = "recent_client_activity"
        case dnsPaused = "dns_paused"
        case protection
        case setupHints = "setup_hints"
    }
}
