//! Ordered schema changes keyed by SQLite `PRAGMA user_version`.
//!
//! - Version **0**: empty or pre-migration DB.
//! - After migration **N**, `user_version == N`.
//! - Add `apply_migration_K` and extend `run_migrations` when the schema changes.

use rusqlite::Connection;

/// Schema version stored in SQLite after all pending migrations run.
pub const CURRENT_SCHEMA_VERSION: i32 = 3;

fn read_user_version(conn: &Connection) -> rusqlite::Result<i32> {
    conn.query_row("PRAGMA user_version", [], |row| row.get(0))
}

fn set_user_version(conn: &Connection, version: i32) -> rusqlite::Result<()> {
    conn.pragma_update(None, "user_version", version)
}

/// Run every migration from `user_version + 1` through `CURRENT_SCHEMA_VERSION`.
pub fn run_migrations(conn: &Connection) -> rusqlite::Result<()> {
    let mut v = read_user_version(conn)?;
    if v > CURRENT_SCHEMA_VERSION {
        return Err(rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_ERROR),
            Some(format!(
                "database user_version ({v}) exceeds engine CURRENT_SCHEMA_VERSION ({CURRENT_SCHEMA_VERSION})"
            )),
        ));
    }

    while v < CURRENT_SCHEMA_VERSION {
        let next = v + 1;
        match next {
            1 => apply_migration_1(conn)?,
            2 => apply_migration_2(conn)?,
            3 => apply_migration_3(conn)?,
            _ => {
                return Err(rusqlite::Error::SqliteFailure(
                    rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_ERROR),
                    Some(format!("no migration defined for step {next}")),
                ));
            }
        }
        set_user_version(conn, next)?;
        v = next;
    }

    Ok(())
}

/// Baseline NetSentrix schema (tables + indexes). Idempotent `CREATE IF NOT EXISTS` for upgrades from legacy init.
fn apply_migration_1(conn: &Connection) -> rusqlite::Result<()> {
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

/// Per-device DNS policy: `normal` | `restricted` (allowlist-only) | `paused` (SERVFAIL) | `blocked` (sinkhole).
fn apply_migration_2(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"ALTER TABLE devices ADD COLUMN dns_policy TEXT NOT NULL DEFAULT 'normal';"#,
    )?;
    Ok(())
}

fn apply_migration_3(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
        ALTER TABLE devices ADD COLUMN tags TEXT NOT NULL DEFAULT '';
        CREATE TABLE IF NOT EXISTS dns_time_overrides (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scope_device_id TEXT,
            start_min INTEGER NOT NULL,
            end_min INTEGER NOT NULL,
            dns_policy TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_dns_time_overrides_scope ON dns_time_overrides(scope_device_id);
        CREATE TABLE IF NOT EXISTS domain_feedback (
            domain TEXT PRIMARY KEY,
            verdict TEXT NOT NULL,
            updated_ms INTEGER NOT NULL
        );
        "#,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_db_reaches_current_version() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();
        assert_eq!(read_user_version(&conn).unwrap(), CURRENT_SCHEMA_VERSION);
    }

    #[test]
    fn second_run_is_noop() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();
        run_migrations(&conn).unwrap();
        assert_eq!(read_user_version(&conn).unwrap(), CURRENT_SCHEMA_VERSION);
    }
}
