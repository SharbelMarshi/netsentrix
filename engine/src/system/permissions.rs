//! Port 53 / BPF capability notes — real checks in packaging phase.

#[allow(dead_code)]
pub fn needs_root_for_dns_port(port: u16) -> bool {
    port == 53
}
