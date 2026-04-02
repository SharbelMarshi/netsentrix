use std::net::SocketAddr;

/// Parse `host:port` or default `:53`.
pub fn parse_upstream(addr: &str) -> anyhow::Result<SocketAddr> {
    let s = addr.trim();
    if let Ok(sa) = s.parse::<SocketAddr>() {
        return Ok(sa);
    }
    Ok(format!("{s}:53").parse()?)
}
