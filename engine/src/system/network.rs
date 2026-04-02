//! LAN / local addressing helpers for setup UI (via API).

use std::net::{IpAddr, Ipv4Addr};

use if_addrs::IfAddr;

/// Best-effort non-loopback private or link-local IPv4 for "engine IP" hints.
pub fn primary_lan_ipv4_string() -> Option<String> {
    let ifs = if_addrs::get_if_addrs().ok()?;
    let mut best: Option<Ipv4Addr> = None;
    for iface in ifs {
        if iface.is_loopback() {
            continue;
        }
        let IfAddr::V4(v4) = iface.addr else {
            continue;
        };
        let ip = v4.ip;
        if ip.is_private() || ip.is_link_local() {
            best = Some(match best {
                None => ip,
                Some(cur) => prefer_ip(cur, ip),
            });
        }
    }
    best.map(|ip| ip.to_string())
}

fn prefer_ip(a: Ipv4Addr, b: Ipv4Addr) -> Ipv4Addr {
    // Prefer 192.168.x.x over 10.x and 172.16-31 (arbitrary home-LAN bias).
    if a.octets()[0] == 192 && a.octets()[1] == 168 {
        return a;
    }
    if b.octets()[0] == 192 && b.octets()[1] == 168 {
        return b;
    }
    b
}

#[allow(dead_code)]
pub fn is_ipv4_global(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => !v4.is_private() && !v4.is_loopback() && !v4.is_link_local(),
        IpAddr::V6(_) => false,
    }
}
