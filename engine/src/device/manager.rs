//! Register devices from observed DNS clients.

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
