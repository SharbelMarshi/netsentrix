use rusqlite::{params, Connection};

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct AlertRow {
    pub id: i64,
    pub timestamp_ms: i64,
    pub device_id: Option<String>,
    pub severity: String,
    pub category: String,
    pub message: String,
    pub details_json: Option<String>,
}

/// Insert a row (e.g. future detection pipeline). Not used by shipping DNS path; schema only.
pub fn insert(
    conn: &Connection,
    timestamp_ms: i64,
    device_id: Option<&str>,
    severity: &str,
    category: &str,
    message: &str,
    details_json: Option<&str>,
) -> rusqlite::Result<i64> {
    conn.execute(
        r#"INSERT INTO alerts (timestamp, device_id, severity, category, message, details_json)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#,
        params![
            timestamp_ms,
            device_id,
            severity,
            category,
            message,
            details_json
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn list_recent(conn: &Connection, limit: u32) -> rusqlite::Result<Vec<AlertRow>> {
    let lim = limit.clamp(1, 500) as i64;
    let mut stmt = conn.prepare(
        r#"SELECT id, timestamp, device_id, severity, category, message, details_json
           FROM alerts ORDER BY id DESC LIMIT ?1"#,
    )?;
    let rows = stmt.query_map(params![lim], |r| {
        Ok(AlertRow {
            id: r.get(0)?,
            timestamp_ms: r.get(1)?,
            device_id: r.get(2)?,
            severity: r.get(3)?,
            category: r.get(4)?,
            message: r.get(5)?,
            details_json: r.get(6)?,
        })
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}
