//! Local user verdicts on domains (FG3) — merged deterministically in classification.

use rusqlite::{params, Connection, OptionalExtension};

pub fn get_verdict(conn: &Connection, domain: &str) -> Option<String> {
    let norm = domain.trim().trim_end_matches('.').to_ascii_lowercase();
    conn.query_row(
        "SELECT verdict FROM domain_feedback WHERE domain = ?1",
        [&norm],
        |r| r.get::<_, String>(0),
    )
    .optional()
    .ok()
    .flatten()
}

pub fn upsert(
    conn: &Connection,
    domain: &str,
    verdict: &str,
    now_ms: i64,
) -> rusqlite::Result<()> {
    let norm = domain.trim().trim_end_matches('.').to_ascii_lowercase();
    conn.execute(
        r#"INSERT INTO domain_feedback (domain, verdict, updated_ms) VALUES (?1, ?2, ?3)
           ON CONFLICT(domain) DO UPDATE SET verdict = excluded.verdict, updated_ms = excluded.updated_ms"#,
        params![norm, verdict, now_ms],
    )?;
    Ok(())
}
