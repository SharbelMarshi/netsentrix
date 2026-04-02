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
    let isProtected: Bool

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

struct DnsSettingsDTO: Decodable, Sendable {
    let upstream: String
    let blockPolicy: String

    enum CodingKeys: String, CodingKey {
        case upstream
        case blockPolicy = "block_policy"
    }
}

struct DnsPatchBody: Encodable {
    let dns: DnsPatchInner
}

struct DnsPatchInner: Encodable {
    var upstream: String?
}

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
