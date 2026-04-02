//! Authoritative protection summary for UI (engine is source of truth).
//!
//! **LAN proof:** `last_query_ms`, `distinct_clients_in_window`, and `lan_query_count_in_window` use
//! **non-loopback** `device_id` rows only (see `storage::queries::NON_LOOPBACK_LAN_DEVICE_SQL`) so localhost
//! tests do not inflate “network” activity.

use std::net::SocketAddr;

use rusqlite::Connection;

use crate::api::models::ProtectionSummary;
use crate::config::schema::EngineConfig;
use crate::dns::server::DnsRuntimeState;
use crate::storage::queries;
use crate::system::runtime::EngineStatus;

pub fn listen_addr_lan_capable(addr: SocketAddr) -> bool {
    !addr.ip().is_loopback()
}

pub fn compute(
    cfg: &EngineConfig,
    dns: &DnsRuntimeState,
    eng: &EngineStatus,
    dns_paused: bool,
    conn: &Connection,
    now_ms: i64,
) -> ProtectionSummary {
    let window_ms = (cfg.dns.protection_activity_window_secs.saturating_mul(1000)) as i64;
    let since = now_ms.saturating_sub(window_ms);
    let dns_listen = cfg.dns.listen_addr.to_string();
    let lan_capable = listen_addr_lan_capable(cfg.dns.listen_addr);

    let last_query_ms = queries::latest_non_loopback_lan_timestamp_ms(conn).ok().flatten();
    let distinct_clients_in_window = queries::count_distinct_non_loopback_clients_since(conn, since)
        .unwrap_or(0);
    let lan_query_count_in_window = queries::count_lan_client_queries_since(conn, since).unwrap_or(0);

    let mut reasons: Vec<String> = Vec::new();
    let state = match eng {
        EngineStatus::Starting => {
            reasons.push("engine_starting".into());
            "not_active".into()
        }
        EngineStatus::Stopped => {
            reasons.push("engine_stopped".into());
            "not_active".into()
        }
        EngineStatus::Error => {
            reasons.push("engine_error".into());
            "not_active".into()
        }
        EngineStatus::Running => {
            if !dns.udp_bound {
                reasons.push("dns_not_bound".into());
                "not_active".into()
            } else if dns_paused {
                reasons.push("dns_paused".into());
                "not_active".into()
            } else if !lan_capable {
                reasons.push("listen_loopback_only".into());
                if distinct_clients_in_window == 0 {
                    reasons.push("no_recent_lan_queries".into());
                }
                "partial".into()
            } else if distinct_clients_in_window == 0 {
                reasons.push("no_recent_lan_queries".into());
                "partial".into()
            } else {
                "active".into()
            }
        }
    };

    ProtectionSummary {
        state,
        reasons,
        window_seconds: cfg.dns.protection_activity_window_secs,
        distinct_clients_in_window,
        lan_query_count_in_window,
        last_query_ms,
        lan_capable,
        dns_listen,
    }
}
