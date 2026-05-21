use rusqlite::{params, Connection, OptionalExtension};

use crate::device::models::DeviceRow;

pub fn upsert_seen(
    conn: &Connection,
    id: &str,
    ip: &str,
    now_ms: i64,
) -> rusqlite::Result<()> {
    conn.execute(
        r#"INSERT INTO devices (id, ip_address, first_seen, last_seen, is_active, is_protected)
           VALUES (?1, ?2, ?3, ?3, 1, 0)
           ON CONFLICT(id) DO UPDATE SET
             last_seen = excluded.last_seen,
             ip_address = excluded.ip_address,
             is_active = 1"#,
        params![id, ip, now_ms],
    )?;
    Ok(())
}

/// Display name for alert/UI copy: saved `name` if non-empty, else `ip_address`, else strip `ip:` from id.
pub fn friendly_display_name(conn: &Connection, device_id: &str) -> String {
    let from_row: Option<String> = conn
        .query_row(
            r#"SELECT COALESCE(NULLIF(TRIM(name), ''), ip_address) FROM devices WHERE id = ?1"#,
            [device_id],
            |r| r.get(0),
        )
        .optional()
        .ok()
        .flatten();
    from_row.unwrap_or_else(|| {
        device_id
            .strip_prefix("ip:")
            .unwrap_or(device_id)
            .to_string()
    })
}

pub fn set_name(conn: &Connection, id: &str, name: &str) -> rusqlite::Result<usize> {
    conn.execute(
        "UPDATE devices SET name = ?2 WHERE id = ?1",
        params![id, name],
    )
}

/// Base policy from `devices.dns_policy`, then optional time-of-day override (Phase 9).
pub fn resolve_effective_dns_policy(conn: &Connection, device_id: &str) -> String {
    let base = get_dns_policy(conn, device_id);
    if let Some(p) = crate::storage::time_overrides::scheduled_override_policy(conn, device_id) {
        if let Some(c) = canonical_dns_policy(&p) {
            return c.to_string();
        }
    }
    base
}

/// Per-device DNS policy stored in SQLite (`dns_policy` column).
pub fn get_dns_policy(conn: &Connection, device_id: &str) -> String {
    conn.query_row(
        "SELECT COALESCE(NULLIF(TRIM(dns_policy), ''), 'normal') FROM devices WHERE id = ?1",
        [device_id],
        |r| r.get::<_, String>(0),
    )
    .unwrap_or_else(|_| "normal".to_string())
}

pub fn set_dns_policy(conn: &Connection, id: &str, policy: &str) -> rusqlite::Result<usize> {
    conn.execute(
        "UPDATE devices SET dns_policy = ?2 WHERE id = ?1",
        params![id, policy],
    )
}

pub fn set_tags(conn: &Connection, id: &str, tags: &str) -> rusqlite::Result<usize> {
    conn.execute(
        "UPDATE devices SET tags = ?2 WHERE id = ?1",
        params![id, tags],
    )
}

/// Returns canonical policy string or `None` if invalid.
pub fn canonical_dns_policy(input: &str) -> Option<&'static str> {
    match input.trim().to_ascii_lowercase().as_str() {
        "normal" => Some("normal"),
        "restricted" => Some("restricted"),
        "paused" => Some("paused"),
        "blocked" => Some("blocked"),
        _ => None,
    }
}

/// List devices with DNS query counts: **total** (lifetime in DB) and **last 24h** (rolling from `now_ms`).
pub fn list_with_query_stats(
    conn: &Connection,
    now_ms: i64,
) -> rusqlite::Result<Vec<(DeviceRow, i64, i64)>> {
    let since_24h = now_ms.saturating_sub(86_400_000);
    let mut stmt = conn.prepare(
        r#"SELECT d.id, d.ip_address, d.mac_address, d.hostname, d.vendor, d.name,
                  d.first_seen, d.last_seen, d.is_active, d.is_protected, d.dns_policy, d.tags,
                  COALESCE((SELECT COUNT(*) FROM dns_queries q WHERE q.device_id = d.id), 0),
                  COALESCE((SELECT COUNT(*) FROM dns_queries q WHERE q.device_id = d.id AND q.timestamp >= ?1), 0)
           FROM devices d
           ORDER BY COALESCE(d.last_seen, 0) DESC"#,
    )?;
    let rows = stmt.query_map(params![since_24h], |r| {
        Ok((
            DeviceRow {
                id: r.get(0)?,
                ip_address: r.get(1)?,
                mac_address: r.get(2)?,
                hostname: r.get(3)?,
                vendor: r.get(4)?,
                name: r.get(5)?,
                first_seen: r.get(6)?,
                last_seen: r.get(7)?,
                is_active: r.get::<_, i64>(8)? != 0,
                is_protected: r.get::<_, i64>(9)? != 0,
                dns_policy: r.get(10)?,
                tags: r.get(11)?,
            },
            r.get::<_, i64>(12)?,
            r.get::<_, i64>(13)?,
        ))
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}

/// Single device with the same query aggregates as [`list_with_query_stats`].
pub fn get_with_query_stats(
    conn: &Connection,
    id: &str,
    now_ms: i64,
) -> rusqlite::Result<Option<(DeviceRow, i64, i64)>> {
    let since_24h = now_ms.saturating_sub(86_400_000);
    let mut stmt = conn.prepare(
        r#"SELECT d.id, d.ip_address, d.mac_address, d.hostname, d.vendor, d.name,
                  d.first_seen, d.last_seen, d.is_active, d.is_protected, d.dns_policy, d.tags,
                  COALESCE((SELECT COUNT(*) FROM dns_queries q WHERE q.device_id = d.id), 0),
                  COALESCE((SELECT COUNT(*) FROM dns_queries q WHERE q.device_id = d.id AND q.timestamp >= ?1), 0)
           FROM devices d WHERE d.id = ?2"#,
    )?;
    let mut rows = stmt.query_map(params![since_24h, id], |r| {
        Ok((
            DeviceRow {
                id: r.get(0)?,
                ip_address: r.get(1)?,
                mac_address: r.get(2)?,
                hostname: r.get(3)?,
                vendor: r.get(4)?,
                name: r.get(5)?,
                first_seen: r.get(6)?,
                last_seen: r.get(7)?,
                is_active: r.get::<_, i64>(8)? != 0,
                is_protected: r.get::<_, i64>(9)? != 0,
                dns_policy: r.get(10)?,
                tags: r.get(11)?,
            },
            r.get::<_, i64>(12)?,
            r.get::<_, i64>(13)?,
        ))
    })?;
    match rows.next() {
        Some(Ok(t)) => Ok(Some(t)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::migrations;

    fn in_memory() -> rusqlite::Connection {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        migrations::run_migrations(&conn).unwrap();
        conn
    }

    #[test]
    fn resolve_effective_dns_policy_reads_device_column() {
        let conn = in_memory();
        conn
            .execute(
                r#"INSERT INTO devices (id, ip_address, first_seen, last_seen, is_active, is_protected, dns_policy, tags)
                   VALUES ('ip:10.0.0.5', '10.0.0.5', 0, 0, 1, 0, 'blocked', '')"#,
                [],
            )
            .unwrap();
        assert_eq!(
            resolve_effective_dns_policy(&conn, "ip:10.0.0.5"),
            "blocked"
        );
    }

    #[test]
    fn resolve_effective_dns_policy_unknown_device_defaults_normal() {
        let conn = in_memory();
        assert_eq!(resolve_effective_dns_policy(&conn, "ip:9.9.9.9"), "normal");
    }

    #[test]
    fn canonical_dns_policy_accepts_variants() {
        assert_eq!(canonical_dns_policy("  BLOCKED  "), Some("blocked"));
        assert_eq!(canonical_dns_policy("nope"), None);
    }
}
