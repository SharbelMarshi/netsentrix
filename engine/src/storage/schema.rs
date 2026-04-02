use rusqlite::Connection;

/// Apply baseline DDL. TODO: versioned migrations.
pub fn init(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS dns_queries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            device_id TEXT,
            domain TEXT NOT NULL,
            query_type TEXT,
            action TEXT NOT NULL,
            upstream_response TEXT,
            latency_ms INTEGER
        );

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            ip_address TEXT NOT NULL,
            mac_address TEXT,
            hostname TEXT,
            vendor TEXT,
            name TEXT,
            first_seen INTEGER,
            last_seen INTEGER,
            is_active INTEGER NOT NULL DEFAULT 1,
            is_protected INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            device_id TEXT,
            severity TEXT NOT NULL,
            category TEXT NOT NULL,
            message TEXT NOT NULL,
            details_json TEXT
        );

        CREATE TABLE IF NOT EXISTS rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            pattern TEXT NOT NULL,
            action TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
        );

        CREATE INDEX IF NOT EXISTS idx_dns_queries_ts ON dns_queries(timestamp);
        CREATE INDEX IF NOT EXISTS idx_dns_queries_domain ON dns_queries(domain);
        CREATE INDEX IF NOT EXISTS idx_dns_queries_device_id ON dns_queries(device_id);
        CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(timestamp);
        "#,
    )?;
    Ok(())
}
