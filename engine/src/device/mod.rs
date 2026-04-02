//! Device registry — [`client_key`] ties DNS clients to `devices.id`; [`manager`] upserts on each logged query.
//!
//! **MVP truth:** devices appear from **DNS query source IPs** only. MAC / hostname / vendor columns are not
//! populated here. Per-device query totals and 24h counts are computed in the devices API from `dns_queries`.

pub mod discovery;
pub mod fingerprint;
pub mod manager;
pub mod models;

/// Stable `devices.id` for DNS clients: `ip:<addr>`.
pub fn client_key(addr: &std::net::SocketAddr) -> String {
    format!("ip:{}", addr.ip())
}
