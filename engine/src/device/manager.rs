//! Register devices from observed DNS clients.
//!
//! Upserts set `is_protected = 0` and only touch IP / seen timestamps — there is no per-device policy
//! in the DNS MVP; API consumers should not treat `is_protected` as meaningful yet.

use rusqlite::Connection;

use crate::storage::devices;

/// Upsert device row from a logged query (`device_id` is `ip:x.x.x.x`).
pub fn touch_seen(conn: &Connection, device_id: &str, timestamp_ms: i64) {
    let Some(ip) = device_id.strip_prefix("ip:") else {
        return;
    };
    if let Err(e) = devices::upsert_seen(conn, device_id, ip, timestamp_ms) {
        tracing::warn!(error = %e, "device upsert failed");
    }
}
