//! Human-readable setup guidance for `GET /health` (`setup_hints`).
//!
//! Derived from [`crate::api::protection`] signals plus **bounded** heuristics. Copy must stay
//! honest: these are hints, not proof of bypass.

use rusqlite::Connection;

use crate::api::models::{ProtectionSummary, SetupHint};
use crate::api::protection::listen_addr_lan_capable;
use crate::config::schema::EngineConfig;
use crate::dns::server::DnsRuntimeState;
use crate::storage::queries;
use crate::system::network::host_has_global_or_unique_local_ipv6;
use crate::system::runtime::EngineStatus;

/// Build ordered hints (warnings first). `conn` is used only for optional DNS-visible heuristics.
pub fn build(
    cfg: &EngineConfig,
    dns: &DnsRuntimeState,
    eng: &EngineStatus,
    dns_paused: bool,
    conn: Option<&Connection>,
    protection: &ProtectionSummary,
    now_ms: i64,
) -> Vec<SetupHint> {
    let mut hints: Vec<SetupHint> = Vec::new();
    let window_ms = (cfg.dns.protection_activity_window_secs.saturating_mul(1000)) as i64;
    let since = now_ms.saturating_sub(window_ms);

    match eng {
        EngineStatus::Starting => hints.push(SetupHint {
            code: "engine_starting".into(),
            severity: "info".into(),
            title: "Engine is starting".into(),
            detail: "Wait a few seconds and refresh health.".into(),
            suggested_fix: None,
        }),
        EngineStatus::Stopped => hints.push(SetupHint {
            code: "engine_stopped".into(),
            severity: "warning".into(),
            title: "Engine stopped".into(),
            detail: "The DNS control plane is not running.".into(),
            suggested_fix: Some("Start the NetSentrix engine service (e.g. launchctl).".into()),
        }),
        EngineStatus::Error => hints.push(SetupHint {
            code: "engine_error".into(),
            severity: "warning".into(),
            title: "Engine reported an error".into(),
            detail: "DNS may not be listening; check engine logs for bind or startup failures."
                .into(),
            suggested_fix: Some("Fix `dns.listen_addr` / permissions (port 53) and restart.".into()),
        }),
        EngineStatus::Running => {}
    }

    if protection.reasons.iter().any(|r| r == "db_unavailable") {
        hints.push(SetupHint {
            code: "db_unavailable".into(),
            severity: "warning".into(),
            title: "Database unavailable".into(),
            detail: "Protection state could not be computed.".into(),
            suggested_fix: Some("Check `storage.db_path` and file permissions.".into()),
        });
    }

    if dns_paused {
        hints.push(SetupHint {
            code: "dns_paused".into(),
            severity: "warning".into(),
            title: "DNS answering is paused".into(),
            detail: "NetSentrix returns SERVFAIL and does not forward while paused.".into(),
            suggested_fix: Some("Use Resume in the app or POST /dns/resume when maintenance is done."
                .into()),
        });
    }

    if matches!(eng, EngineStatus::Running) && !dns.udp_bound {
        let err = dns
            .udp_last_error
            .as_deref()
            .unwrap_or("UDP DNS listener not bound");
        hints.push(SetupHint {
            code: "dns_not_bound".into(),
            severity: "warning".into(),
            title: "DNS UDP listener is not bound".into(),
            detail: err.to_string(),
            suggested_fix: Some(
                "Free the port, adjust `dns.listen_addr` in config.toml, and restart the engine."
                    .into(),
            ),
        });
    }

    let lan_capable = listen_addr_lan_capable(cfg.dns.listen_addr);
    if matches!(eng, EngineStatus::Running)
        && dns.udp_bound
        && !dns_paused
        && !lan_capable
    {
        hints.push(SetupHint {
            code: "listen_loopback_only".into(),
            severity: "warning".into(),
            title: "DNS is bound to loopback only".into(),
            detail: "LAN devices cannot send DNS to this resolver unless it listens on a LAN address (e.g. 0.0.0.0:53)."
                .into(),
            suggested_fix: Some(
                "Set `dns.listen_addr` to an interface reachable from your LAN and restart."
                    .into(),
            ),
        });
    }

    if matches!(eng, EngineStatus::Running)
        && dns.udp_bound
        && !dns_paused
        && lan_capable
        && protection.distinct_clients_in_window == 0
    {
        hints.push(SetupHint {
            code: "no_lan_clients_in_window".into(),
            severity: "warning".into(),
            title: "No LAN client DNS seen in the activity window".into(),
            detail: format!(
                "No non-loopback client queries logged in the last {} seconds.",
                protection.window_seconds
            ),
            suggested_fix: Some(
                "Point the router’s DHCP DNS (or per-device DNS) at this Mac’s LAN IP. Confirm with the Queries screen."
                    .into(),
            ),
        });
    }

    if matches!(eng, EngineStatus::Running)
        && dns.udp_bound
        && !dns_paused
        && lan_capable
        && protection.distinct_clients_in_window == 0
    {
        hints.push(SetupHint {
            code: "router_dns_may_not_point_here".into(),
            severity: "info".into(),
            title: "Router may not be using NetSentrix yet".into(),
            detail: "Absence of LAN queries usually means clients are not using this resolver — it is not definitive."
                .into(),
            suggested_fix: Some(
                "Update router DHCP DNS to this Mac’s IP, renew leases, then refresh.".into(),
            ),
        });
    }

    if host_has_global_or_unique_local_ipv6() {
        hints.push(SetupHint {
            code: "ipv6_dns_bypass_possible".into(),
            severity: "info".into(),
            title: "IPv6 may bypass this DNS path".into(),
            detail: "This Mac has global or unique-local IPv6. Some clients prefer IPv6 resolvers that are not your router’s IPv4 DNS setting."
                .into(),
            suggested_fix: Some(
                "On your router, configure IPv6 DNS (or disable IPv6 DNS) per your network design — NetSentrix cannot change router settings."
                    .into(),
            ),
        });
    }

    if let Some(conn) = conn {
        if let Ok(true) = queries::any_recent_doh_like_hostname(conn, since) {
            hints.push(SetupHint {
                code: "possible_doh_hostname_in_queries".into(),
                severity: "info".into(),
                title: "Queries look like public DoH/DoT provider hostnames".into(),
                detail: "Some logged names match common DNS-over-HTTPS providers. That only means a client asked your resolver about those names — not that bypass occurred."
                    .into(),
                suggested_fix: Some(
                    "If you need stricter control, review client DoH settings on devices you manage."
                        .into(),
                ),
            });
        }
    }

    dedupe_by_code(hints)
}

fn dedupe_by_code(mut hints: Vec<SetupHint>) -> Vec<SetupHint> {
    let mut seen = std::collections::HashSet::<String>::new();
    hints.retain(|h| seen.insert(h.code.clone()));
    hints.sort_by(|a, b| {
        let aw = if a.severity == "warning" { 0 } else { 1 };
        let bw = if b.severity == "warning" { 0 } else { 1 };
        aw.cmp(&bw).then_with(|| a.code.cmp(&b.code))
    });
    hints
}
