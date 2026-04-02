//! Serializable engine configuration (TOML).

use std::net::SocketAddr;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EngineConfig {
    pub api: ApiSection,
    pub dns: DnsSection,
    pub storage: StorageSection,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ApiSection {
    /// e.g. `127.0.0.1:8756`
    pub listen_addr: SocketAddr,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum BlockPolicy {
    /// Respond with `A` → 0.0.0.0 (and `AAAA` → ::) when applicable.
    #[default]
    AZero,
    /// Respond with `NXDOMAIN` for blocked names.
    NxDomain,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DnsSection {
    /// UDP bind; use non-`:53` for unprivileged dev.
    pub listen_addr: SocketAddr,
    /// Upstream resolver `host:port`.
    pub upstream: String,
    /// One domain per line; `#` starts a comment; empty lines ignored.
    #[serde(default)]
    pub blocklist_paths: Vec<PathBuf>,
    #[serde(default)]
    pub allowlist_paths: Vec<PathBuf>,
    #[serde(default)]
    pub block_policy: BlockPolicy,
    /// Positive / negative response cache for forwarded answers.
    #[serde(default)]
    pub cache: DnsCacheConfig,
    /// Sliding window (seconds) for protection / `recent_client_activity` signals.
    #[serde(default = "default_protection_window_secs")]
    pub protection_activity_window_secs: u64,
}

fn default_protection_window_secs() -> u64 {
    300
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DnsCacheConfig {
    #[serde(default = "default_cache_enabled")]
    pub enabled: bool,
    #[serde(default = "default_cache_max_entries")]
    pub max_entries: usize,
    #[serde(default = "default_cache_max_ttl_secs")]
    pub max_ttl_secs: u32,
    #[serde(default = "default_cache_min_ttl_secs")]
    pub min_ttl_secs: u32,
    #[serde(default = "default_cache_default_positive_ttl_secs")]
    pub default_positive_ttl_secs: u32,
    #[serde(default = "default_cache_negative_ttl_secs")]
    pub negative_ttl_secs: u32,
}

impl Default for DnsCacheConfig {
    fn default() -> Self {
        Self {
            enabled: default_cache_enabled(),
            max_entries: default_cache_max_entries(),
            max_ttl_secs: default_cache_max_ttl_secs(),
            min_ttl_secs: default_cache_min_ttl_secs(),
            default_positive_ttl_secs: default_cache_default_positive_ttl_secs(),
            negative_ttl_secs: default_cache_negative_ttl_secs(),
        }
    }
}

fn default_cache_enabled() -> bool {
    true
}
fn default_cache_max_entries() -> usize {
    10_000
}
fn default_cache_max_ttl_secs() -> u32 {
    3600
}
fn default_cache_min_ttl_secs() -> u32 {
    1
}
fn default_cache_default_positive_ttl_secs() -> u32 {
    60
}
fn default_cache_negative_ttl_secs() -> u32 {
    300
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct StorageSection {
    pub db_path: PathBuf,
}
