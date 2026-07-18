//! Normalized engine events — extend in Phase 1 (DNS) and Phase 3 (packets, alerts).

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct DnsQueryEvent {
    pub domain: String,
    pub client_ip: String,
    pub action: String,
    pub query_type: String,
}
