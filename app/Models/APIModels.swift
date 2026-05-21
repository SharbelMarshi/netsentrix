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
    /// Stored per-device mode in SQLite (`normal`, `restricted`, `paused`, `blocked`).
    let dnsPolicy: String
    /// Mode the resolver uses now (stored policy plus an active local time override when one matches).
    let effectiveDnsPolicy: String
    /// True when a `dns_time_overrides` row applies to this device at engine local wall time.
    let scheduleOverrideActive: Bool
    /// Comma-separated operator tags (FG4).
    let tags: String

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
        case dnsPolicy = "dns_policy"
        case effectiveDnsPolicy = "effective_dns_policy"
        case scheduleOverrideActive = "schedule_override_active"
        case tags
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
        dnsPolicy = try c.decodeIfPresent(String.self, forKey: .dnsPolicy) ?? "normal"
        effectiveDnsPolicy = try c.decodeIfPresent(String.self, forKey: .effectiveDnsPolicy) ?? dnsPolicy
        scheduleOverrideActive = try c.decodeIfPresent(Bool.self, forKey: .scheduleOverrideActive) ?? false
        tags = try c.decodeIfPresent(String.self, forKey: .tags) ?? ""
    }

    /// True when saved SQLite policy differs from what the resolver uses right now (usually a time override).
    var effectiveDiffersFromStored: Bool {
        dnsPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            != effectiveDnsPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct InsightsDailyDTO: Decodable, Sendable {
    let windowHours: UInt32
    let sinceMs: Int64
    let untilMs: Int64
    let topDevices: [DeviceQueryInsightRow]
    let topDomains: [DomainInsightRowDTO]
    let peakHourLocal: Int?
    let peakHourQueryCount: Int64

    enum CodingKeys: String, CodingKey {
        case windowHours = "window_hours"
        case sinceMs = "since_ms"
        case untilMs = "until_ms"
        case topDevices = "top_devices"
        case topDomains = "top_domains"
        case peakHourLocal = "peak_hour_local"
        case peakHourQueryCount = "peak_hour_query_count"
    }
}

struct DeviceQueryInsightRow: Decodable, Sendable {
    let deviceId: String
    let queryCount: Int64

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case queryCount = "query_count"
    }
}

struct DomainInsightRowDTO: Decodable, Sendable, Identifiable {
    var id: String { domain }
    let domain: String
    let queryCount: Int64
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case domain
        case queryCount = "query_count"
        case explanation
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
    /// `low` | `medium` | `high` from engine rules; absent on older engines.
    let priority: String?

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs = "timestamp_ms"
        case deviceId = "device_id"
        case severity
        case category
        case message
        case detailsJson = "details_json"
        case priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        timestampMs = try c.decode(Int64.self, forKey: .timestampMs)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId)
        severity = try c.decode(String.self, forKey: .severity)
        category = try c.decode(String.self, forKey: .category)
        message = try c.decode(String.self, forKey: .message)
        detailsJson = try c.decodeIfPresent(String.self, forKey: .detailsJson)
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
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
    let blocklistPaths: [String]
    let allowlistPaths: [String]

    enum CodingKeys: String, CodingKey {
        case listenAddr = "listen_addr"
        case upstream
        case blockPolicy = "block_policy"
        case protectionActivityWindowSecs = "protection_activity_window_secs"
        case blocklistPaths = "blocklist_paths"
        case allowlistPaths = "allowlist_paths"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listenAddr = try c.decode(String.self, forKey: .listenAddr)
        upstream = try c.decode(String.self, forKey: .upstream)
        blockPolicy = try c.decode(String.self, forKey: .blockPolicy)
        protectionActivityWindowSecs = try c.decodeIfPresent(UInt64.self, forKey: .protectionActivityWindowSecs) ?? 300
        blocklistPaths = try c.decodeIfPresent([String].self, forKey: .blocklistPaths) ?? []
        allowlistPaths = try c.decodeIfPresent([String].self, forKey: .allowlistPaths) ?? []
    }
}

/// POST `/settings` body: only encode keys you intend to change.
struct SettingsDnsPatch: Encodable {
    var upstream: String?
    var blockPolicy: String?
    var protectionActivityWindowSecs: UInt64?
    var blocklistPaths: [String]?
    var allowlistPaths: [String]?

    enum CodingKeys: String, CodingKey {
        case upstream
        case blockPolicy = "block_policy"
        case protectionActivityWindowSecs = "protection_activity_window_secs"
        case blocklistPaths = "blocklist_paths"
        case allowlistPaths = "allowlist_paths"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(upstream, forKey: .upstream)
        try c.encodeIfPresent(blockPolicy, forKey: .blockPolicy)
        try c.encodeIfPresent(protectionActivityWindowSecs, forKey: .protectionActivityWindowSecs)
        try c.encodeIfPresent(blocklistPaths, forKey: .blocklistPaths)
        try c.encodeIfPresent(allowlistPaths, forKey: .allowlistPaths)
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
