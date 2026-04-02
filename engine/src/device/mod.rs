//! Device registry — [`client_key`] ties DNS clients to `devices.id`; [`manager`] upserts on each logged query.

pub mod discovery;
pub mod fingerprint;
pub mod manager;
pub mod models;

/// Stable `devices.id` for DNS clients: `ip:<addr>`.
pub fn client_key(addr: &std::net::SocketAddr) -> String {
    format!("ip:{}", addr.ip())
}
