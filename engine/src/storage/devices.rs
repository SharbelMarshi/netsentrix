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

/// List devices with DNS query counts: **total** (lifetime in DB) and **last 24h** (rolling from `now_ms`).
pub fn list_with_query_stats(
    conn: &Connection,
    now_ms: i64,
) -> rusqlite::Result<Vec<(DeviceRow, i64, i64)>> {
    let since_24h = now_ms.saturating_sub(86_400_000);
    let mut stmt = conn.prepare(
        r#"SELECT d.id, d.ip_address, d.mac_address, d.hostname, d.vendor, d.name,
                  d.first_seen, d.last_seen, d.is_active, d.is_protected,
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
            },
            r.get::<_, i64>(10)?,
            r.get::<_, i64>(11)?,
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
                  d.first_seen, d.last_seen, d.is_active, d.is_protected,
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
            },
            r.get::<_, i64>(10)?,
            r.get::<_, i64>(11)?,
        ))
    })?;
    match rows.next() {
        Some(Ok(t)) => Ok(Some(t)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}
