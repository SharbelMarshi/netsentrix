use rusqlite::{params, Connection};

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

pub fn set_name(conn: &Connection, id: &str, name: &str) -> rusqlite::Result<usize> {
    conn.execute(
        "UPDATE devices SET name = ?2 WHERE id = ?1",
        params![id, name],
    )
}

pub fn list_all(conn: &Connection) -> rusqlite::Result<Vec<DeviceRow>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, ip_address, mac_address, hostname, vendor, name,
                  first_seen, last_seen, is_active, is_protected
           FROM devices ORDER BY last_seen DESC"#,
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(DeviceRow {
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
        })
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}

pub fn get(conn: &Connection, id: &str) -> rusqlite::Result<Option<DeviceRow>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, ip_address, mac_address, hostname, vendor, name,
                  first_seen, last_seen, is_active, is_protected
           FROM devices WHERE id = ?1"#,
    )?;
    let mut rows = stmt.query_map(params![id], |r| {
        Ok(DeviceRow {
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
        })
    })?;
    match rows.next() {
        Some(Ok(d)) => Ok(Some(d)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}
