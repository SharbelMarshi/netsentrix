import Foundation

struct ApiEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: ApiErrorBody?
}

struct ApiErrorBody: Decodable {
    let code: String
    let message: String
}

struct StatsPayload: Decodable, Sendable {
    let totalQueries: Int64
    let blockedQueries: Int64
    let allowedQueries: Int64
    let blockedPercent: Double
    let distinctDevices: Int64
    let alertsTotal: Int64
    let alertsLast24h: Int64
    let dnsCacheHits: UInt64?
    let dnsCacheMisses: UInt64?
    /// `AVG(latency_ms)` over `dns_queries` rows with latency (older engines omit).
    let dnsAvgLatencyMs: Double?
    let dnsLatencySampleCount: Int64?

    enum CodingKeys: String, CodingKey {
        case totalQueries = "total_queries"
        case blockedQueries = "blocked_queries"
        case allowedQueries = "allowed_queries"
        case blockedPercent = "blocked_percent"
        case distinctDevices = "distinct_devices"
        case alertsTotal = "alerts_total"
        case alertsLast24h = "alerts_last_24h"
        case dnsCacheHits = "dns_cache_hits"
        case dnsCacheMisses = "dns_cache_misses"
        case dnsAvgLatencyMs = "dns_avg_latency_ms"
        case dnsLatencySampleCount = "dns_latency_sample_count"
    }

    /// Rows used for `dnsAvgLatencyMs` (0 if unknown or older engine).
    var resolvedLatencySampleCount: Int64 {
        dnsLatencySampleCount ?? 0
    }
}

struct DnsQueryItem: Decodable, Identifiable, Sendable {
    let id: Int64
    let timestampMs: Int64
    let deviceId: String?
    let domain: String
    let queryType: String
    let action: String
    let latencyMs: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case deviceId = "device_id"
        case domain
        case queryType = "query_type"
        case action
        case latencyMs = "latency_ms"
    }

    /// Live WebSocket rows use a negative id (no DB row).
    init(liveTimestamp: Int64, deviceId: String?, domain: String, queryType: String, action: String) {
        self.id = liveTimestamp > 0 ? -liveTimestamp : liveTimestamp
        self.timestampMs = liveTimestamp
        self.deviceId = deviceId
        self.domain = domain
        self.queryType = queryType
        self.action = action
        self.latencyMs = nil
    }

    /// Logged outcome for this row (not the live rules table — use for row tinting only).
    var isBlockedOutcome: Bool {
        let a = action.lowercased()
        return a.contains("block")
    }

    var isAllowedOutcome: Bool {
        let a = action.lowercased()
        return a.contains("allow") && !a.contains("block")
    }
}

struct DeviceDTO: Decodable, Identifiable, Sendable {
    let id: String
    let ipAddress: String
    let macAddress: String?
    let hostname: String?
    let vendor: String?
    let name: String?
    let firstSeen: Int64?
    let lastSeen: Int64?
    let isActive: Bool
    /// Reserved in engine — always false in DNS MVP; not “protected” in product terms.
    let isProtected: Bool
    /// Lifetime `dns_queries` rows for this device in SQLite.
    let queryCountTotal: Int64
    /// Rolling 24h window (engine clock at request time).
    let queryCount24h: Int64
    /// True when `last_seen` is within that 24h window.
    let recentlySeenDns: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case ipAddress = "ip_address"
        case macAddress = "mac_address"
        case hostname
        case vendor
        case name
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case isActive = "is_active"
        case isProtected = "is_protected"
        case queryCountTotal = "query_count_total"
        case queryCount24h = "query_count_24h"
        case recentlySeenDns = "recently_seen_dns"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ipAddress = try c.decode(String.self, forKey: .ipAddress)
        macAddress = try c.decodeIfPresent(String.self, forKey: .macAddress)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        firstSeen = try c.decodeIfPresent(Int64.self, forKey: .firstSeen)
        lastSeen = try c.decodeIfPresent(Int64.self, forKey: .lastSeen)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        isProtected = try c.decode(Bool.self, forKey: .isProtected)
        queryCountTotal = try c.decodeIfPresent(Int64.self, forKey: .queryCountTotal) ?? 0
        queryCount24h = try c.decodeIfPresent(Int64.self, forKey: .queryCount24h) ?? 0
        recentlySeenDns = try c.decodeIfPresent(Bool.self, forKey: .recentlySeenDns) ?? false
    }
}

struct AlertDTO: Decodable, Identifiable, Sendable {
    let id: Int64
    let timestampMs: Int64
    let deviceId: String?
    let severity: String
    let category: String
    let message: String
    let detailsJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case deviceId = "device_id"
        case severity
        case category
        case message
        case detailsJson = "details_json"
    }
}

struct SettingsPayload: Decodable, Sendable {
    let dns: DnsSettingsDTO
    let apiListen: String

    enum CodingKeys: String, CodingKey {
        case dns
        case apiListen = "api_listen"
    }
}

/// Subset of engine `dns` section from `GET /settings` (extra JSON keys ignored).
struct DnsSettingsDTO: Decodable, Sendable {
    let listenAddr: String
    let upstream: String
    let blockPolicy: String
    let protectionActivityWindowSecs: UInt64

    enum CodingKeys: String, CodingKey {
        case listenAddr = "listen_addr"
        case upstream
        case blockPolicy = "block_policy"
        case protectionActivityWindowSecs = "protection_activity_window_secs"
    }
}

/// POST `/settings` body: only encode keys you intend to change.
struct SettingsDnsPatch: Encodable {
    var upstream: String?
    var blockPolicy: String?
    var protectionActivityWindowSecs: UInt64?

    enum CodingKeys: String, CodingKey {
        case upstream
        case blockPolicy = "block_policy"
        case protectionActivityWindowSecs = "protection_activity_window_secs"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(upstream, forKey: .upstream)
        try c.encodeIfPresent(blockPolicy, forKey: .blockPolicy)
        try c.encodeIfPresent(protectionActivityWindowSecs, forKey: .protectionActivityWindowSecs)
    }
}

struct SettingsPostBody: Encodable {
    let dns: SettingsDnsPatch
}

struct EmptyJSON: Encodable {}

/// Engine WebSocket `GET /ws` JSON (subset).
struct WsDnsEvent: Decodable, Sendable {
    let type: String
    let timestamp: Int64
    let deviceId: String?
    let payload: Payload

    struct Payload: Decodable, Sendable {
        let domain: String
        let action: String
        let clientIp: String

        enum CodingKeys: String, CodingKey {
            case domain, action
            case clientIp = "client_ip"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, timestamp
        case deviceId = "device_id"
        case payload
    }
}
