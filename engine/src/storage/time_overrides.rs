//! Time-of-day DNS policy overrides (Phase 9 v1). Evaluated in **local** wall time via `chrono::Local`.

use chrono::Timelike;
use rusqlite::{params, Connection};

#[derive(Debug, Clone)]
pub struct TimeOverrideRow {
    pub id: i64,
    pub scope_device_id: Option<String>,
    pub start_min: i32,
    pub end_min: i32,
    pub dns_policy: String,
    pub enabled: bool,
}

/// Inclusive window; supports overnight when `start_min > end_min`.
pub fn minute_in_window(minute: i32, start: i32, end: i32) -> bool {
    if start <= end {
        minute >= start && minute <= end
    } else {
        minute >= start || minute <= end
    }
}

/// If any enabled override matches **local** time and scope, returns its `dns_policy`.
/// **Precedence:** device-scoped rows beat global (`scope_device_id IS NULL`); then higher `id` wins.
pub fn scheduled_override_policy(conn: &Connection, device_id: &str) -> Option<String> {
    let now = chrono::Local::now();
    let minute = (now.hour() as i32) * 60 + now.minute() as i32;

    let mut stmt = conn
        .prepare(
            r#"SELECT id, scope_device_id, start_min, end_min, dns_policy, enabled
               FROM dns_time_overrides WHERE enabled = 1
                 AND (scope_device_id IS NULL OR scope_device_id = ?1)
               ORDER BY CASE WHEN scope_device_id IS NOT NULL THEN 0 ELSE 1 END, id DESC"#,
        )
        .ok()?;

    let rows = stmt
        .query_map(params![device_id], |r| {
            Ok(TimeOverrideRow {
                id: r.get(0)?,
                scope_device_id: r.get(1)?,
                start_min: r.get(2)?,
                end_min: r.get(3)?,
                dns_policy: r.get(4)?,
                enabled: r.get::<_, i64>(5)? != 0,
            })
        })
        .ok()?;

    for row in rows.flatten() {
        if !row.enabled {
            continue;
        }
        if minute_in_window(minute, row.start_min, row.end_min) {
            return Some(row.dns_policy);
        }
    }
    None
}

pub fn list_all(conn: &Connection) -> rusqlite::Result<Vec<TimeOverrideRow>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, scope_device_id, start_min, end_min, dns_policy, enabled
           FROM dns_time_overrides ORDER BY id ASC"#,
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(TimeOverrideRow {
            id: r.get(0)?,
            scope_device_id: r.get(1)?,
            start_min: r.get(2)?,
            end_min: r.get(3)?,
            dns_policy: r.get(4)?,
            enabled: r.get::<_, i64>(5)? != 0,
        })
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}

pub fn insert(
    conn: &Connection,
    scope_device_id: Option<&str>,
    start_min: i32,
    end_min: i32,
    dns_policy: &str,
) -> rusqlite::Result<i64> {
    conn.execute(
        r#"INSERT INTO dns_time_overrides (scope_device_id, start_min, end_min, dns_policy, enabled)
           VALUES (?1, ?2, ?3, ?4, 1)"#,
        params![scope_device_id, start_min, end_min, dns_policy],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn delete_by_id(conn: &Connection, id: i64) -> rusqlite::Result<usize> {
    conn.execute("DELETE FROM dns_time_overrides WHERE id = ?1", params![id])
}
