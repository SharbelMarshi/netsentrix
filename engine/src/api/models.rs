use serde::{Deserialize, Serialize};

use crate::config::schema::{BlockPolicy, DnsSection, EngineConfig};

/// Authoritative protection summary (engine-computed).
#[derive(Debug, Serialize, Clone)]
pub struct ProtectionSummary {
    /// `not_active` | `partial` | `active`
    pub state: String,
    pub reasons: Vec<String>,
    pub window_seconds: u64,
    pub distinct_clients_in_window: i64,
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

/// Export engine config subset for API (clone dns + api listen).
pub fn settings_from_config(cfg: &EngineConfig) -> SettingsResponse {
    SettingsResponse {
        dns: cfg.dns.clone(),
        api_listen: cfg.api.listen_addr.to_string(),
    }
}
