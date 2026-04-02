//! Turn raw libpcap frames into [`PacketEvent`] (no side effects).

use etherparse::{NetSlice, SlicedPacket, TransportSlice};
use std::net::Ipv4Addr;

use super::models::PacketEvent;

/// libpcap / DLT values we handle explicitly; others fall through the trial chain.
pub const DLT_EN10MB: i32 = 1;
pub const DLT_RAW: i32 = 12;
pub const DLT_LINUX_SLL: i32 = 113;
pub const DLT_LINUX_SLL2: i32 = 276;

pub fn normalize_capture(dlt: i32, data: &[u8], timestamp_ms: i64) -> Option<PacketEvent> {
    if data.is_empty() {
        return None;
    }

    let sliced: Option<SlicedPacket<'_>> = match dlt {
        DLT_EN10MB => SlicedPacket::from_ethernet(data).ok(),
        DLT_LINUX_SLL | DLT_LINUX_SLL2 => SlicedPacket::from_linux_sll(data).ok(),
        DLT_RAW => SlicedPacket::from_ip(data).ok(),
        _ => SlicedPacket::from_ethernet(data)
            .ok()
            .or_else(|| SlicedPacket::from_linux_sll(data).ok())
            .or_else(|| SlicedPacket::from_ip(data).ok()),
    };

    let Some(s) = sliced else {
        tracing::trace!(dlt, len = data.len(), "sniffer: could not slice packet");
        return None;
    };

    let (src_ip, dst_ip, base_proto, ip_payload_len) = match &s.net {
        Some(NetSlice::Ipv4(ipv4)) => {
            let h = &ipv4.header;
            let src = h.source_addr().to_string();
            let dst = h.destination_addr().to_string();
            let proto = ip_protocol_name(h.protocol().0);
            let plen = Some(ipv4.header.total_len() as u32);
            (src, dst, proto, plen)
        }
        Some(NetSlice::Ipv6(ipv6)) => {
            let h = &ipv6.header;
            let src = h.source_addr().to_string();
            let dst = h.destination_addr().to_string();
            let proto = ip_protocol_name(ipv6.payload().ip_number.0);
            let plen = None;
            (src, dst, proto, plen)
        }
        Some(NetSlice::Arp(arp)) => {
            let sender = arp.sender_protocol_addr();
            let target = arp.target_protocol_addr();
            if sender.len() == 4 && target.len() == 4 {
                let src = Ipv4Addr::new(sender[0], sender[1], sender[2], sender[3]).to_string();
                let dst = Ipv4Addr::new(target[0], target[1], target[2], target[3]).to_string();
                (
                    src,
                    dst,
                    "ARP".to_string(),
                    Some(data.len() as u32),
                )
            } else {
                ("0.0.0.0".to_string(), "0.0.0.0".to_string(), "ARP".to_string(), Some(data.len() as u32))
            }
        }
        None => {
            tracing::trace!("sniffer: no L3 in sliced packet");
            return None;
        }
    };

    let (protocol, src_port, dst_port, flags, raw_info) = match &s.transport {
        Some(TransportSlice::Udp(u)) => (
            format!("UDP/{base_proto}"),
            Some(u.source_port()),
            Some(u.destination_port()),
            None,
            None,
        ),
        Some(TransportSlice::Tcp(t)) => {
            let f = tcp_flag_summary(t);
            (
                format!("TCP/{base_proto}"),
                Some(t.source_port()),
                Some(t.destination_port()),
                Some(f),
                None,
            )
        }
        Some(TransportSlice::Icmpv4(_)) => ("ICMPv4".to_string(), None, None, None, None),
        Some(TransportSlice::Icmpv6(_)) => ("ICMPv6".to_string(), None, None, None, None),
        None => (base_proto, None, None, None, None),
    };

    Some(PacketEvent {
        timestamp_ms,
        src_ip,
        dst_ip,
        protocol,
        src_port,
        dst_port,
        length: ip_payload_len.or(Some(data.len() as u32)),
        flags,
        raw_protocol_info: raw_info,
        device_id: None,
    })
}

fn ip_protocol_name(n: u8) -> String {
    match n {
        1 => "ICMP".to_string(),
        6 => "TCP".to_string(),
        17 => "UDP".to_string(),
        58 => "ICMPv6".to_string(),
        _ => format!("IP-{}", n),
    }
}

fn tcp_flag_summary(t: &etherparse::TcpSlice<'_>) -> String {
    let mut parts = Vec::new();
    if t.fin() {
        parts.push("FIN");
    }
    if t.syn() {
        parts.push("SYN");
    }
    if t.rst() {
        parts.push("RST");
    }
    if t.psh() {
        parts.push("PSH");
    }
    if t.ack() {
        parts.push("ACK");
    }
    if t.urg() {
        parts.push("URG");
    }
    if parts.is_empty() {
        "—".to_string()
    } else {
        parts.join("+")
    }
}
