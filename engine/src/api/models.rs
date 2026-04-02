use serde::{Deserialize, Serialize};

use crate::config::schema::{BlockPolicy, DnsSection, EngineConfig};
use crate::device::models::DeviceRow;

/// Authoritative protection summary (engine-computed).
#[derive(Debug, Serialize, Clone)]
pub struct ProtectionSummary {
    /// `not_active` | `partial` | `active`
    pub state: String,
    pub reasons: Vec<String>,
    pub window_seconds: u64,
    pub distinct_clients_in_window: i64,
    /// Rows from **non-loopback** LAN `device_id` keys in the sliding window (volume).
    pub lan_query_count_in_window: i64,
    /// Latest `dns_queries.timestamp` from non-loopback LAN clients (not localhost test traffic).
    pub last_query_ms: Option<i64>,
    pub lan_capable: bool,
    pub dns_listen: String,
}

impl ProtectionSummary {
    pub fn db_unavailable(window_seconds: u64, dns_listen: String) -> Self {
        Self {
            state: "not_active".into(),
            reasons: vec!["db_unavailable".into()],
            window_seconds,
            distinct_clients_in_window: 0,
            lan_query_count_in_window: 0,
            last_query_ms: None,
            lan_capable: false,
            dns_listen,
        }
    }
}

/// Flat health (compat with early app); includes setup hints.
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub ok: bool,
    pub version: &'static str,
    pub engine: &'static str,
    pub api_listen: String,
    pub dns_listen: String,
    /// Same as `dns_udp_bound` (legacy field for older clients).
    pub dns_bound: bool,
    /// UDP DNS listener on `dns_listen`.
    pub dns_udp_bound: bool,
    /// TCP DNS listener on `dns_listen` (large responses / RFC 7766 clients).
    pub dns_tcp_bound: bool,
    /// Last UDP bind error, if any.
    pub dns_last_error: Option<String>,
    /// Last TCP bind error, if any.
    pub dns_tcp_last_error: Option<String>,
    pub engine_status: String,
    pub suggested_lan_ip: Option<String>,
    /// Always `false` in MVP — libpcap capture is not shipped (see `sniffer` module DTOs only).
    pub sniffer_enabled: bool,
    pub alerts_total: i64,
    pub api_token_file: String,
    /// Epoch ms of newest `dns_queries` row, if any.
    pub last_client_query_ms: Option<i64>,
    /// True if a query was logged within `protection_activity_window_secs` (same window as `protection`).
    pub recent_client_activity: bool,
    pub dns_paused: bool,
    pub protection: ProtectionSummary,
    /// Resolved config file path (same as startup).
    pub config_path: String,
    /// Directory containing `api.token` and default DB basename (`.../NetSentrix`).
    pub netsentrix_data_dir: String,
    /// SQLite path from active config.
    pub db_path: String,
}

#[derive(Debug, Serialize)]
pub struct ApiEnvelope<T: Serialize> {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ApiErrorBody>,
}

#[derive(Debug, Serialize)]
pub struct ApiErrorBody {
    pub code: String,
    pub message: String,
}

impl<T: Serialize> ApiEnvelope<T> {
    pub fn ok(data: T) -> Self {
        Self {
            ok: true,
            data: Some(data),
            error: None,
        }
    }
}

impl ApiEnvelope<()> {
    pub fn err(code: impl Into<String>, message: impl Into<String>) -> ApiEnvelope<()> {
        ApiEnvelope {
            ok: false,
            data: None,
            error: Some(ApiErrorBody {
                code: code.into(),
                message: message.into(),
            }),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct StatsResponse {
    pub total_queries: i64,
    /// `blocked` + `blocked_forwarded` query log rows.
    pub blocked_queries: i64,
    /// `allowed` + `allowed_cached` query log rows.
    pub allowed_queries: i64,
    pub blocked_percent: f64,
    pub distinct_devices: i64,
    pub alerts_total: i64,
    pub alerts_last_24h: i64,
    /// DNS response cache lookups (hits / misses) when cache is enabled.
    pub dns_cache_hits: u64,
    pub dns_cache_misses: u64,
    /// Mean `latency_ms` over logged queries that have latency (forwarded path), or absent if none.
    pub dns_avg_latency_ms: Option<f64>,
    /// Row count included in the average.
    pub dns_latency_sample_count: i64,
}

#[derive(Debug, Deserialize)]
pub struct SettingsPatch {
    #[serde(default)]
    pub dns: Option<DnsPatch>,
}

#[derive(Debug, Deserialize)]
pub struct DnsPatch {
    pub upstream: Option<String>,
    pub blocklist_paths: Option<Vec<std::path::PathBuf>>,
    pub allowlist_paths: Option<Vec<std::path::PathBuf>>,
    pub block_policy: Option<BlockPolicy>,
    pub protection_activity_window_secs: Option<u64>,
}

#[derive(Debug, Serialize)]
pub struct SettingsResponse {
    pub dns: DnsSection,
    pub api_listen: String,
}

#[derive(Debug, Deserialize)]
pub struct PatternBody {
    pub pattern: String,
}

#[derive(Debug, Deserialize)]
pub struct DevicePatchBody {
    pub name: String,
}

/// Device row returned by `GET /devices` and `GET /devices/:id` (DNS-visibility MVP).
#[derive(Debug, Serialize)]
pub struct DeviceResponse {
    pub id: String,
    pub ip_address: String,
    pub mac_address: Option<String>,
    pub hostname: Option<String>,
    pub vendor: Option<String>,
    pub name: Option<String>,
    pub first_seen: Option<i64>,
    pub last_seen: Option<i64>,
    /// Currently always `true` on upsert; not a staleness signal until TTL logic exists.
    pub is_active: bool,
    /// Reserved for future per-device policy — **always `false`** in the DNS-only MVP (do not map to “protected” UX).
    pub is_protected: bool,
    /// All `dns_queries` rows for this `device_id` in the database.
    pub query_count_total: i64,
    /// Queries with `timestamp` in the **rolling 24 hours** before the API handler’s `now` (epoch ms).
    pub query_count_24h: i64,
    /// `true` when `last_seen` is within that same rolling 24h window.
    pub recently_seen_dns: bool,
}

impl DeviceResponse {
    pub fn from_parts(row: DeviceRow, query_total: i64, query_24h: i64, now_ms: i64) -> Self {
        let win_start = now_ms.saturating_sub(86_400_000);
        let recently_seen_dns = row
            .last_seen
            .map(|t| t >= win_start)
            .unwrap_or(false);
        Self {
            id: row.id,
            ip_address: row.ip_address,
            mac_address: row.mac_address,
            hostname: row.hostname,
            vendor: row.vendor,
            name: row.name,
            first_seen: row.first_seen,
            last_seen: row.last_seen,
            is_active: row.is_active,
            is_protected: row.is_protected,
            query_count_total: query_total,
            query_count_24h: query_24h,
            recently_seen_dns,
        }
    }
}

/// Export engine config subset for API (clone dns + api listen).
pub fn settings_from_config(cfg: &EngineConfig) -> SettingsResponse {
    SettingsResponse {
        dns: cfg.dns.clone(),
        api_listen: cfg.api.listen_addr.to_string(),
    }
}
