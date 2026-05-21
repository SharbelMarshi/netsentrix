use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone)]
pub struct DnsQueryRow {
    pub timestamp_ms: i64,
    pub device_id: Option<String>,
    pub domain: String,
    pub query_type: String,
    pub action: String,
    pub upstream_response: Option<String>,
    pub latency_ms: Option<i64>,
}

pub fn insert(conn: &Connection, row: &DnsQueryRow) -> rusqlite::Result<i64> {
    conn.execute(
        r#"INSERT INTO dns_queries (
            timestamp, device_id, domain, query_type, action, upstream_response, latency_ms
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
        params![
            row.timestamp_ms,
            row.device_id,
            row.domain,
            row.query_type,
            row.action,
            row.upstream_response,
            row.latency_ms,
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Latest `dns_queries.timestamp` (epoch ms), **any** row (includes loopback). Prefer [`latest_non_loopback_lan_timestamp_ms`] for LAN proof.
#[allow(dead_code)]
pub fn latest_timestamp_ms(conn: &Connection) -> rusqlite::Result<Option<i64>> {
    conn.query_row("SELECT MAX(timestamp) FROM dns_queries", [], |r| r.get(0))
        .optional()
}

/// SQL predicate: rows tied to a likely **LAN** client (`ip:` key, not loopback / not `::1`).
pub const NON_LOOPBACK_LAN_DEVICE_SQL: &str = "device_id IS NOT NULL \
     AND device_id LIKE 'ip:%' \
     AND device_id NOT LIKE 'ip:127.%' \
     AND device_id != 'ip:::1'";

/// Latest query time from **non-loopback** `device_id` rows only (proof of LAN DNS through NetSentrix).
pub fn latest_non_loopback_lan_timestamp_ms(conn: &Connection) -> rusqlite::Result<Option<i64>> {
    let sql = format!(
        "SELECT MAX(timestamp) FROM dns_queries WHERE {}",
        NON_LOOPBACK_LAN_DEVICE_SQL
    );
    conn.query_row(&sql, [], |r| r.get(0)).optional()
}

/// Count of logged queries in the window from non-loopback LAN clients (volume, not distinct IPs).
pub fn count_lan_client_queries_since(conn: &Connection, since_ms: i64) -> rusqlite::Result<i64> {
    let sql = format!(
        "SELECT COUNT(*) FROM dns_queries WHERE timestamp >= ?1 AND ({})",
        NON_LOOPBACK_LAN_DEVICE_SQL
    );
    conn.query_row(&sql, [since_ms], |r| r.get(0))
}

/// Distinct `device_id` values in the window with `ip:` prefix excluding loopback-looking IDs.
pub fn count_distinct_non_loopback_clients_since(
    conn: &Connection,
    since_ms: i64,
) -> rusqlite::Result<i64> {
    conn.query_row(
        &format!(
            "SELECT COUNT(DISTINCT device_id) FROM dns_queries WHERE timestamp >= ?1 AND ({})",
            NON_LOOPBACK_LAN_DEVICE_SQL
        ),
        [since_ms],
        |r| r.get(0),
    )
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DnsQueryListItem {
    pub id: i64,
    pub timestamp_ms: i64,
    pub device_id: Option<String>,
    pub domain: String,
    pub query_type: String,
    pub action: String,
    pub latency_ms: Option<i64>,
}

/// Newest first. `before_id` optional cursor (exclusive). `device_id` restricts rows to one client key (`ip:…`).
pub fn list_recent(
    conn: &Connection,
    limit: u32,
    before_id: Option<i64>,
    device_id: Option<&str>,
) -> rusqlite::Result<Vec<DnsQueryListItem>> {
    let limit = limit.clamp(1, 500) as i64;
    let mut out = Vec::new();
    let map_row = |r: &rusqlite::Row<'_>| {
        Ok(DnsQueryListItem {
            id: r.get(0)?,
            timestamp_ms: r.get(1)?,
            device_id: r.get(2)?,
            domain: r.get(3)?,
            query_type: r.get(4)?,
            action: r.get(5)?,
            latency_ms: r.get(6)?,
        })
    };
    match (before_id, device_id) {
        (Some(bid), Some(did)) => {
            let mut stmt = conn.prepare(
                r#"SELECT id, timestamp, device_id, domain, query_type, action, latency_ms
                   FROM dns_queries WHERE device_id = ?1 AND id < ?2
                   ORDER BY id DESC LIMIT ?3"#,
            )?;
            let rows = stmt.query_map(params![did, bid, limit], map_row)?;
            for row in rows {
                out.push(row?);
            }
        }
        (None, Some(did)) => {
            let mut stmt = conn.prepare(
                r#"SELECT id, timestamp, device_id, domain, query_type, action, latency_ms
                   FROM dns_queries WHERE device_id = ?1
                   ORDER BY id DESC LIMIT ?2"#,
            )?;
            let rows = stmt.query_map(params![did, limit], map_row)?;
            for row in rows {
                out.push(row?);
            }
        }
        (Some(bid), None) => {
            let mut stmt = conn.prepare(
                r#"SELECT id, timestamp, device_id, domain, query_type, action, latency_ms
                   FROM dns_queries WHERE id < ?1
                   ORDER BY id DESC LIMIT ?2"#,
            )?;
            let rows = stmt.query_map(params![bid, limit], map_row)?;
            for row in rows {
                out.push(row?);
            }
        }
        (None, None) => {
            let mut stmt = conn.prepare(
                r#"SELECT id, timestamp, device_id, domain, query_type, action, latency_ms
                   FROM dns_queries
                   ORDER BY id DESC LIMIT ?1"#,
            )?;
            let rows = stmt.query_map(params![limit], map_row)?;
            for row in rows {
                out.push(row?);
            }
        }
    }
    Ok(out)
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct QueryStats {
    pub total_queries: i64,
    pub blocked_queries: i64,
    pub allowed_queries: i64,
    pub distinct_devices: i64,
}

pub fn aggregate_stats(conn: &Connection) -> rusqlite::Result<QueryStats> {
    let total: i64 = conn
        .query_row("SELECT COUNT(*) FROM dns_queries", [], |r| r.get(0))
        .unwrap_or(0);
    let blocked: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM dns_queries WHERE action IN ('blocked', 'blocked_forwarded')"#,
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let allowed: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM dns_queries WHERE action IN ('allowed', 'allowed_cached')"#,
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let distinct: i64 = conn
        .query_row(
            "SELECT COUNT(DISTINCT device_id) FROM dns_queries WHERE device_id IS NOT NULL",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    Ok(QueryStats {
        total_queries: total,
        blocked_queries: blocked,
        allowed_queries: allowed,
        distinct_devices: distinct,
    })
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct LatencyAggregate {
    /// `AVG(latency_ms)` over rows where latency was recorded (typically upstream forwards).
    pub avg_latency_ms: Option<f64>,
    pub latency_sample_count: i64,
}

/// DNS-visible substrings matching common DoH/DoT provider hostnames (bounded LIKE scan).
const DOH_HOSTNAME_FRAGMENTS: &[&str] = &[
    "dns.google",
    "cloudflare-dns.com",
    "dns.cloudflare.com",
    "mozilla.cloudflare-dns.com",
    "dns.quad9.net",
    "dns9.quad9.net",
    "dns11.quad9.net",
    "doh.opendns.com",
    "dns.nextdns.io",
    "doh.dns.sb",
    "one.one.one.one",
];

/// Whether any recent query `domain` contains a known DoH-style hostname fragment.
pub fn any_recent_doh_like_hostname(conn: &Connection, since_ms: i64) -> rusqlite::Result<bool> {
    let mut sql = String::from(
        "SELECT 1 FROM dns_queries WHERE timestamp >= ?1 AND (",
    );
    for (i, frag) in DOH_HOSTNAME_FRAGMENTS.iter().enumerate() {
        if i > 0 {
            sql.push_str(" OR ");
        }
        sql.push_str("domain LIKE '%");
        // Safe: `frag` is ASCII constant, no user input.
        sql.push_str(frag);
        sql.push_str("%'");
    }
    sql.push_str(") LIMIT 1");
    let mut stmt = conn.prepare(&sql)?;
    let found = stmt.exists([since_ms])?;
    Ok(found)
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DeviceQueryCount {
    pub device_id: String,
    pub query_count: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DomainQueryCount {
    pub domain: String,
    pub query_count: i64,
}

/// Top `device_id` keys by row count since `since_ms`.
pub fn top_devices_since(
    conn: &Connection,
    since_ms: i64,
    limit: i32,
) -> rusqlite::Result<Vec<DeviceQueryCount>> {
    let lim = limit.clamp(1, 50) as i64;
    let mut stmt = conn.prepare(
        r#"SELECT device_id, COUNT(*) FROM dns_queries
           WHERE device_id IS NOT NULL AND timestamp >= ?1
           GROUP BY device_id ORDER BY COUNT(*) DESC LIMIT ?2"#,
    )?;
    let rows = stmt.query_map(params![since_ms, lim], |r| {
        Ok(DeviceQueryCount {
            device_id: r.get(0)?,
            query_count: r.get(1)?,
        })
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}

pub fn top_domains_since(
    conn: &Connection,
    since_ms: i64,
    limit: i32,
) -> rusqlite::Result<Vec<DomainQueryCount>> {
    let lim = limit.clamp(1, 50) as i64;
    let mut stmt = conn.prepare(
        r#"SELECT domain, COUNT(*) FROM dns_queries
           WHERE timestamp >= ?1
           GROUP BY domain ORDER BY COUNT(*) DESC LIMIT ?2"#,
    )?;
    let rows = stmt.query_map(params![since_ms, lim], |r| {
        Ok(DomainQueryCount {
            domain: r.get(0)?,
            query_count: r.get(1)?,
        })
    })?;
    let mut v = Vec::new();
    for row in rows {
        v.push(row?);
    }
    Ok(v)
}

/// Hour 0–23 in **local** time with the highest query volume since `since_ms`.
pub fn peak_hour_local_since(
    conn: &Connection,
    since_ms: i64,
) -> rusqlite::Result<Option<(i32, i64)>> {
    let mut stmt = conn.prepare(
        r#"SELECT CAST(strftime('%H', datetime(timestamp/1000, 'unixepoch', 'localtime')) AS INTEGER) as hr,
                  COUNT(*) as c
           FROM dns_queries WHERE timestamp >= ?1
           GROUP BY hr ORDER BY c DESC LIMIT 1"#,
    )?;
    let mut rows = stmt.query_map(params![since_ms], |r| {
        Ok((r.get::<_, i32>(0)?, r.get::<_, i64>(1)?))
    })?;
    match rows.next() {
        Some(Ok(t)) => Ok(Some(t)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

pub fn aggregate_latency(conn: &Connection) -> rusqlite::Result<LatencyAggregate> {
    let (avg, n): (Option<f64>, i64) = conn.query_row(
        r#"SELECT AVG(latency_ms), COUNT(*) FROM dns_queries WHERE latency_ms IS NOT NULL"#,
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    Ok(LatencyAggregate {
        avg_latency_ms: avg,
        latency_sample_count: n,
    })
}
