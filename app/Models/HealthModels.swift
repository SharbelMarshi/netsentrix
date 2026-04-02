import Foundation

/// Engine-computed protection summary (`GET /health` → `protection`).
struct ProtectionSummaryDTO: Codable, Sendable {
    let state: String
    let reasons: [String]
    let windowSeconds: UInt64
    let distinctClientsInWindow: Int64
    let lastQueryMs: Int64?
    let lanCapable: Bool
    let dnsListen: String

    enum CodingKeys: String, CodingKey {
        case state, reasons
        case windowSeconds = "window_seconds"
        case distinctClientsInWindow = "distinct_clients_in_window"
        case lastQueryMs = "last_query_ms"
        case lanCapable = "lan_capable"
        case dnsListen = "dns_listen"
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
    /// Newest `dns_queries` timestamp (epoch ms), if any.
    let lastClientQueryMs: Int64?
    /// Query logged within `protection.window_seconds` (aligned with engine protection window).
    let recentClientActivity: Bool?
    /// DNS answering paused (SERVFAIL); `POST /dns/pause` / `POST /dns/resume` or toggle `POST /pause`.
    let dnsPaused: Bool?
    /// Authoritative protection state from the engine; nil if talking to an older engine.
    let protection: ProtectionSummaryDTO?

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
        case lastClientQueryMs = "last_client_query_ms"
        case recentClientActivity = "recent_client_activity"
        case dnsPaused = "dns_paused"
        case protection
    }
}
