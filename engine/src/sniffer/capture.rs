//! libpcap capture loop — forwards raw frames only (no detection).

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Context;
use pcap::{Capture, Device};

/// Open the best default capture device: prefer first non-loopback, else any.
pub fn open_capture() -> anyhow::Result<Capture<pcap::Active>> {
    let devices = Device::list().context("pcap Device::list")?;
    let chosen = devices
        .into_iter()
        .find(|d| !d.name.contains("lo") && !d.name.contains("loopback"))
        .or_else(Device::lookup)
        .ok_or_else(|| anyhow::anyhow!("no pcap devices"))?;

    let mut cap = Capture::from_device(chosen)
        .context("Capture::from_device")?
        .immediate_mode(true)
        .open()
        .context("pcap open")?;

    cap.set_snap_len(65535)
        .context("set_snap_len")?;
    // Responsive shutdown: wake periodically from next_packet.
    cap.set_timeout(250).context("set_timeout")?;
    // IPv4, IPv6, ARP — enough for normalize + activity without DNS-only noise from all ether.
    cap.filter("ip or ip6 or arp", true).context("set BPF filter")?;

    Ok(cap)
}

pub fn now_epoch_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn ts_to_ms(ts: &libc::timeval) -> i64 {
    (ts.tv_sec as i64) * 1000 + (ts.tv_usec as i64) / 1000
}

pub const READ_TIMEOUT: Duration = Duration::from_millis(300);
