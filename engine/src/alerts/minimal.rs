//! Simple post-query checks against SQLite. Cooldowns use recent `alerts` rows (same category + scope).

use std::collections::{BTreeMap, BTreeSet, HashMap};

use rusqlite::{params, Connection};
use serde_json::json;

use crate::sniffer::models::DetectionEvent;
use crate::storage::{alerts, devices, queries};

use super::classification::{classify_domain_with_feedback, DomainCategory};

const WINDOW_MS: i64 = 60_000;
const BURST_THRESHOLD: i64 = 90;
const MANY_DOMAINS_THRESHOLD: i64 = 45;
const REPEAT_BLOCK_WINDOW_MS: i64 = 600_000;
const REPEAT_BLOCK_THRESHOLD: i64 = 10;
const GLOBAL_SPIKE_THRESHOLD: i64 = 800;

const BURST_COOLDOWN_MS: i64 = 300_000;
const MANY_DOMAINS_COOLDOWN_MS: i64 = 600_000;
const REPEAT_BLOCK_COOLDOWN_MS: i64 = 1_800_000;
const GLOBAL_SPIKE_COOLDOWN_MS: i64 = 300_000;

const CAT_BURST: &str = "dns_burst";
const CAT_MANY_DOMAINS: &str = "dns_many_domains";
const CAT_REPEAT_BLOCK: &str = "dns_repeat_block";
const CAT_GLOBAL_SPIKE: &str = "dns_global_spike";

const MAX_ALERTS_PER_QUERY: usize = 2;

const MOSTLY_COMMON_RATIO: f64 = 0.7;
const MOSTLY_UNKNOWN_RATIO: f64 = 0.6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TrafficProfile {
    MostlyCommon,
    Mixed,
    MostlyUnknown,
}

impl TrafficProfile {
    fn as_str(self) -> &'static str {
        match self {
            Self::MostlyCommon => "mostly_common",
            Self::Mixed => "mixed",
            Self::MostlyUnknown => "mostly_unknown",
        }
    }
}

#[derive(Debug, Default)]
struct DomainWindowSummary {
    total_queries: i64,
    distinct_domains: i64,
    common_queries: i64,
    unknown_queries: i64,
    common_distinct_domains: i64,
    unknown_distinct_domains: i64,
    common_family_counts: BTreeMap<&'static str, i64>,
    /// Top domains by query count in the window (cap ~10) for actionable alert context.
    top_domains_sample: Vec<String>,
    /// Unknown-classified domains by query count (cap ~8) for “suspicious” quick actions.
    top_unknown_domains_sample: Vec<String>,
}

fn top_domains_by_query_count(domains: &[String], take: usize) -> Vec<String> {
    let mut counts: HashMap<String, i64> = HashMap::new();
    for d in domains {
        let k = d.to_ascii_lowercase();
        *counts.entry(k).or_insert(0) += 1;
    }
    let mut pairs: Vec<(String, i64)> = counts.into_iter().collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    pairs.into_iter().take(take).map(|(s, _)| s).collect()
}

fn top_unknown_domains_by_query_count(
    conn: Option<&Connection>,
    domains: &[String],
    take: usize,
) -> Vec<String> {
    let mut counts: HashMap<String, i64> = HashMap::new();
    for d in domains {
        if classify_domain_with_feedback(conn, d).category != DomainCategory::Unknown {
            continue;
        }
        let k = d.to_ascii_lowercase();
        *counts.entry(k).or_insert(0) += 1;
    }
    let mut pairs: Vec<(String, i64)> = counts.into_iter().collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    pairs.into_iter().take(take).map(|(s, _)| s).collect()
}

impl DomainWindowSummary {
    fn from_domains(conn: Option<&Connection>, domains: Vec<String>) -> Self {
        let top_domains_sample = top_domains_by_query_count(&domains, 10);
        let top_unknown_domains_sample = top_unknown_domains_by_query_count(conn, &domains, 8);
        let mut summary = Self {
            total_queries: domains.len() as i64,
            top_domains_sample,
            top_unknown_domains_sample,
            ..Self::default()
        };
        let mut distinct = BTreeSet::new();

        for domain in &domains {
            let classification = classify_domain_with_feedback(conn, domain);
            match classification.category {
                DomainCategory::Common => {
                    summary.common_queries += 1;
                    if let Some(family) = classification.family {
                        *summary.common_family_counts.entry(family).or_insert(0) += 1;
                    }
                }
                DomainCategory::Unknown => summary.unknown_queries += 1,
            }
            distinct.insert(domain.to_ascii_lowercase());
        }

        summary.distinct_domains = distinct.len() as i64;
        for domain in distinct {
            match classify_domain_with_feedback(conn, &domain).category {
                DomainCategory::Common => summary.common_distinct_domains += 1,
                DomainCategory::Unknown => summary.unknown_distinct_domains += 1,
            }
        }

        summary
    }

    fn candidate_block_domain(&self, profile: TrafficProfile) -> Option<String> {
        match profile {
            TrafficProfile::MostlyUnknown => self
                .top_unknown_domains_sample
                .first()
                .cloned()
                .or_else(|| self.top_domains_sample.first().cloned()),
            TrafficProfile::Mixed => self
                .top_unknown_domains_sample
                .first()
                .cloned()
                .or_else(|| self.top_domains_sample.first().cloned()),
            TrafficProfile::MostlyCommon => None,
        }
    }

    fn query_profile(&self) -> TrafficProfile {
        classify_ratio(
            self.unknown_queries,
            self.total_queries,
            self.common_queries,
        )
    }

    fn distinct_profile(&self) -> TrafficProfile {
        classify_ratio(
            self.unknown_distinct_domains,
            self.distinct_domains,
            self.common_distinct_domains,
        )
    }

    fn top_common_families(&self) -> Vec<&'static str> {
        let mut families: Vec<(&'static str, i64)> = self
            .common_family_counts
            .iter()
            .map(|(family, count)| (*family, *count))
            .collect();
        families.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
        families
            .into_iter()
            .take(3)
            .map(|(family, _)| family)
            .collect()
    }

    /// `device_id`: scope of the alert (per-device categories). `related_device_id`: optional client that
    /// triggered evaluation when the alert row’s `device_id` column is NULL (e.g. global spike).
    /// `trigger_domain`: query that participated in firing this evaluation (compact hint for UI).
    fn details_json(
        &self,
        profile: TrafficProfile,
        device_id: Option<&str>,
        related_device_id: Option<&str>,
        trigger_domain: Option<&str>,
        intel_signals: &[String],
    ) -> String {
        let mut obj = serde_json::Map::new();
        obj.insert(
            "traffic_profile".into(),
            json!(profile.as_str()),
        );
        obj.insert("total_queries".into(), json!(self.total_queries));
        obj.insert("distinct_domains".into(), json!(self.distinct_domains));
        obj.insert("common_queries".into(), json!(self.common_queries));
        obj.insert("unknown_queries".into(), json!(self.unknown_queries));
        obj.insert(
            "common_distinct_domains".into(),
            json!(self.common_distinct_domains),
        );
        obj.insert(
            "unknown_distinct_domains".into(),
            json!(self.unknown_distinct_domains),
        );
        obj.insert(
            "common_families".into(),
            json!(self.top_common_families()),
        );
        obj.insert("top_domains".into(), json!(&self.top_domains_sample));
        obj.insert(
            "top_unknown_domains".into(),
            json!(&self.top_unknown_domains_sample),
        );
        if let Some(d) = trigger_domain {
            if !d.is_empty() {
                obj.insert("trigger_domain".into(), json!(d));
            }
        }
        if let Some(c) = self.candidate_block_domain(profile) {
            if !c.is_empty() {
                obj.insert("candidate_block_domain".into(), json!(c));
            }
        }
        if let Some(d) = device_id {
            obj.insert("device_id".into(), json!(d));
        }
        if let Some(d) = related_device_id {
            obj.insert("related_device_id".into(), json!(d));
        }
        if !intel_signals.is_empty() {
            obj.insert("intel_signals".into(), json!(intel_signals));
        }
        serde_json::Value::Object(obj).to_string()
    }
}

pub fn evaluate_after_query(conn: &Connection, row: &queries::DnsQueryRow) -> Vec<DetectionEvent> {
    let now_ms = row.timestamp_ms;
    let mut out = Vec::new();

    let device_id = match row.device_id.as_deref() {
        Some(d) if d.starts_with("ip:") => Some(d),
        _ => None,
    };

    // 1) Repeated blocked lookups (same device + domain)
    if is_blocked_action(&row.action) {
        if let Some(did) = device_id {
            let since_rb = now_ms.saturating_sub(REPEAT_BLOCK_WINDOW_MS);
            let n_block: i64 = conn
                .query_row(
                    r#"SELECT COUNT(*) FROM dns_queries
                       WHERE device_id = ?1 AND domain = ?2 AND timestamp >= ?3
                         AND action IN ('blocked', 'blocked_forwarded')"#,
                    params![did, &row.domain, since_rb],
                    |r| r.get(0),
                )
                .unwrap_or(0);
            if n_block >= REPEAT_BLOCK_THRESHOLD {
                let details = serde_json::json!({
                    "domain": row.domain,
                    "device_id": did,
                    "trigger_domain": row.domain,
                    "candidate_block_domain": row.domain,
                    "top_unknown_domains": serde_json::Value::Array(vec![]),
                    "intel_signals": [
                        "rule:dns_repeat_block",
                        format!("blocked_lookups≥{} in {}min window", REPEAT_BLOCK_THRESHOLD, REPEAT_BLOCK_WINDOW_MS / 60_000),
                    ],
                })
                .to_string();
                if !repeat_block_in_cooldown(conn, did, &details, now_ms) {
                    let label = devices::friendly_display_name(conn, did);
                    let msg = format!(
                        "Repeated blocked domain requests from {} for “{}”",
                        label, row.domain
                    );
                    try_push_alert(
                        conn,
                        now_ms,
                        Some(did),
                        "warning",
                        CAT_REPEAT_BLOCK,
                        &msg,
                        Some(details.as_str()),
                        &mut out,
                    );
                }
            }
        }
    }

    if out.len() >= MAX_ALERTS_PER_QUERY {
        return out;
    }

    // 2) Per-device burst
    if let Some(did) = device_id {
        let since = now_ms.saturating_sub(WINDOW_MS);
        let summary = load_device_window_summary(conn, did, since).unwrap_or_default();
        let n = summary.total_queries;
        if n >= BURST_THRESHOLD
            && !category_device_cooldown(conn, CAT_BURST, Some(did), now_ms, BURST_COOLDOWN_MS)
        {
            let label = devices::friendly_display_name(conn, did);
            let profile = summary.query_profile();
            let sig = vec![
                format!(
                    "rule:dns_burst (≥{BURST_THRESHOLD} queries / {}s)",
                    WINDOW_MS / 1000
                ),
                format!("observed_queries={n}"),
                format!("traffic_profile={}", profile.as_str()),
            ];
            let details = summary.details_json(
                profile,
                Some(did),
                None,
                Some(row.domain.as_str()),
                &sig,
            );
            let (severity, msg) = match profile {
                TrafficProfile::MostlyCommon => (
                    "info",
                    format!("High DNS activity from {label} appears mostly common service traffic"),
                ),
                TrafficProfile::MostlyUnknown => (
                    "warning",
                    format!("High DNS activity detected from {label} (mostly unknown domains)"),
                ),
                TrafficProfile::Mixed => (
                    "warning",
                    format!("High DNS activity detected from {label}"),
                ),
            };
            try_push_alert(
                conn,
                now_ms,
                Some(did),
                severity,
                CAT_BURST,
                &msg,
                Some(details.as_str()),
                &mut out,
            );
        }
    }

    if out.len() >= MAX_ALERTS_PER_QUERY {
        return out;
    }

    // 3) Many distinct domains from one device
    if let Some(did) = device_id {
        let since = now_ms.saturating_sub(WINDOW_MS);
        let summary = load_device_window_summary(conn, did, since).unwrap_or_default();
        let distinct = summary.distinct_domains;
        if distinct >= MANY_DOMAINS_THRESHOLD
            && !category_device_cooldown(
                conn,
                CAT_MANY_DOMAINS,
                Some(did),
                now_ms,
                MANY_DOMAINS_COOLDOWN_MS,
            )
        {
                let profile = summary.distinct_profile();
                if profile != TrafficProfile::MostlyCommon {
                    let label = devices::friendly_display_name(conn, did);
                    let sig = vec![
                        format!(
                            "rule:dns_many_domains (≥{MANY_DOMAINS_THRESHOLD} distinct / {}s)",
                            WINDOW_MS / 1000
                        ),
                        format!("observed_distinct_domains={distinct}"),
                        format!("distinct_bucket_profile={}", profile.as_str()),
                    ];
                    let details = summary.details_json(
                        profile,
                        Some(did),
                        None,
                        Some(row.domain.as_str()),
                        &sig,
                    );
                    let (severity, msg) = match profile {
                    TrafficProfile::MostlyUnknown => (
                        "warning",
                        format!(
                            "Many different domains queried from {label} (mostly unknown domains)"
                        ),
                    ),
                    TrafficProfile::Mixed => (
                        "info",
                        format!("Many different domains queried from {label} in a short time"),
                    ),
                    TrafficProfile::MostlyCommon => unreachable!(),
                };
                try_push_alert(
                    conn,
                    now_ms,
                    Some(did),
                    severity,
                    CAT_MANY_DOMAINS,
                    &msg,
                    Some(details.as_str()),
                    &mut out,
                );
            }
        }
    }

    if out.len() >= MAX_ALERTS_PER_QUERY {
        return out;
    }

    // 4) Global spike
    let since = now_ms.saturating_sub(WINDOW_MS);
    let summary = load_global_window_summary(conn, since).unwrap_or_default();
    let total = summary.total_queries;
    if total >= GLOBAL_SPIKE_THRESHOLD
        && !category_device_cooldown(
            conn,
            CAT_GLOBAL_SPIKE,
            None,
            now_ms,
            GLOBAL_SPIKE_COOLDOWN_MS,
        )
    {
        let profile = summary.query_profile();
        let related = row
            .device_id
            .as_deref()
            .filter(|d| d.starts_with("ip:"));
        let sig = vec![
            format!(
                "rule:dns_global_spike (≥{GLOBAL_SPIKE_THRESHOLD} queries / {}s)",
                WINDOW_MS / 1000
            ),
            format!("observed_total_queries={total}"),
            format!("traffic_profile={}", profile.as_str()),
        ];
        let details = summary.details_json(
            profile,
            None,
            related,
            Some(row.domain.as_str()),
            &sig,
        );
        let (severity, msg) = match profile {
            TrafficProfile::MostlyCommon => (
                "info",
                "Network-wide DNS spike appears mostly common service traffic",
            ),
            TrafficProfile::MostlyUnknown => (
                "warning",
                "Network-wide DNS spike detected (mostly unknown domains)",
            ),
            TrafficProfile::Mixed => (
                "warning",
                "Very high DNS query volume across all clients in the last minute",
            ),
        };
        try_push_alert(
            conn,
            now_ms,
            None,
            severity,
            CAT_GLOBAL_SPIKE,
            msg,
            Some(details.as_str()),
            &mut out,
        );
    }

    out
}

fn classify_ratio(unknown_count: i64, total_count: i64, common_count: i64) -> TrafficProfile {
    if total_count <= 0 {
        return TrafficProfile::Mixed;
    }
    let unknown_ratio = unknown_count as f64 / total_count as f64;
    let common_ratio = common_count as f64 / total_count as f64;
    if unknown_ratio >= MOSTLY_UNKNOWN_RATIO {
        TrafficProfile::MostlyUnknown
    } else if common_ratio >= MOSTLY_COMMON_RATIO {
        TrafficProfile::MostlyCommon
    } else {
        TrafficProfile::Mixed
    }
}

fn load_device_window_summary(
    conn: &Connection,
    device_id: &str,
    since_ms: i64,
) -> rusqlite::Result<DomainWindowSummary> {
    let domains = load_domains(
        conn,
        "SELECT domain FROM dns_queries WHERE device_id = ?1 AND timestamp >= ?2",
        params![device_id, since_ms],
    )?;
    Ok(DomainWindowSummary::from_domains(Some(conn), domains))
}

fn load_global_window_summary(
    conn: &Connection,
    since_ms: i64,
) -> rusqlite::Result<DomainWindowSummary> {
    let domains = load_domains(
        conn,
        "SELECT domain FROM dns_queries WHERE timestamp >= ?1",
        params![since_ms],
    )?;
    Ok(DomainWindowSummary::from_domains(Some(conn), domains))
}

fn load_domains<P: rusqlite::Params>(
    conn: &Connection,
    sql: &str,
    params: P,
) -> rusqlite::Result<Vec<String>> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(params, |row| row.get::<_, String>(0))?;
    let mut domains = Vec::new();
    for row in rows {
        domains.push(row?);
    }
    Ok(domains)
}

fn try_push_alert(
    conn: &Connection,
    now_ms: i64,
    device_id: Option<&str>,
    severity: &str,
    category: &str,
    message: &str,
    details_json: Option<&str>,
    out: &mut Vec<DetectionEvent>,
) {
    if out.len() >= MAX_ALERTS_PER_QUERY {
        return;
    }
    if let Err(e) = alerts::insert(
        conn,
        now_ms,
        device_id,
        severity,
        category,
        message,
        details_json,
    ) {
        tracing::warn!(error = %e, category, "alert insert failed");
        return;
    }
    out.push(DetectionEvent {
        timestamp_ms: now_ms,
        severity: severity.to_string(),
        category: category.to_string(),
        message: message.to_string(),
        src_ip: device_id
            .and_then(|s| s.strip_prefix("ip:"))
            .unwrap_or("0.0.0.0")
            .to_string(),
        related_ports: None,
    });
}

fn is_blocked_action(action: &str) -> bool {
    matches!(action, "blocked" | "blocked_forwarded")
}

fn category_device_cooldown(
    conn: &Connection,
    category: &str,
    device_id: Option<&str>,
    now_ms: i64,
    cooldown_ms: i64,
) -> bool {
    let since = now_ms.saturating_sub(cooldown_ms);
    let n: i64 = match device_id {
        Some(d) => conn
            .query_row(
                "SELECT COUNT(*) FROM alerts WHERE category = ?1 AND device_id = ?2 AND timestamp >= ?3",
                params![category, d, since],
                |r| r.get(0),
            )
            .unwrap_or(0),
        None => conn
            .query_row(
                "SELECT COUNT(*) FROM alerts WHERE category = ?1 AND device_id IS NULL AND timestamp >= ?2",
                params![category, since],
                |r| r.get(0),
            )
            .unwrap_or(0),
    };
    n > 0
}

fn repeat_block_in_cooldown(
    conn: &Connection,
    device_id: &str,
    details_json: &str,
    now_ms: i64,
) -> bool {
    let since = now_ms.saturating_sub(REPEAT_BLOCK_COOLDOWN_MS);
    let n: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM alerts
               WHERE category = ?1 AND device_id = ?2 AND details_json = ?3 AND timestamp >= ?4"#,
            params![CAT_REPEAT_BLOCK, device_id, details_json, since],
            |r| r.get(0),
        )
        .unwrap_or(0);
    n > 0
}

#[cfg(test)]
mod tests {
    use super::{evaluate_after_query, CAT_BURST, CAT_MANY_DOMAINS};
    use crate::storage::{alerts, migrations, queries};
    use rusqlite::Connection;

    fn setup_conn() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        migrations::run_migrations(&conn).unwrap();
        conn
    }

    fn insert_queries(conn: &Connection, device_id: &str, domains: &[String], base_ts: i64) {
        for (idx, domain) in domains.iter().enumerate() {
            queries::insert(
                conn,
                &queries::DnsQueryRow {
                    timestamp_ms: base_ts + idx as i64,
                    device_id: Some(device_id.to_string()),
                    domain: domain.clone(),
                    query_type: "A".into(),
                    action: "allowed".into(),
                    upstream_response: None,
                    latency_ms: None,
                },
            )
            .unwrap();
        }
    }

    #[test]
    fn burst_from_common_domains_is_softened() {
        let conn = setup_conn();
        let domains = (0..90)
            .map(|idx| {
                if idx % 2 == 0 {
                    format!("api{}.apple.com", idx)
                } else {
                    format!("lh{}.googleapis.com", idx)
                }
            })
            .collect::<Vec<_>>();
        insert_queries(&conn, "ip:192.168.1.10", &domains, 1_000);

        let events = evaluate_after_query(
            &conn,
            &queries::DnsQueryRow {
                timestamp_ms: 1_089,
                device_id: Some("ip:192.168.1.10".into()),
                domain: "lh89.googleapis.com".into(),
                query_type: "A".into(),
                action: "allowed".into(),
                upstream_response: None,
                latency_ms: None,
            },
        );

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].severity, "info");

        let rows = alerts::list_recent(&conn, 10).unwrap();
        assert_eq!(rows[0].category, CAT_BURST);
        assert!(rows[0].message.contains("mostly common service traffic"));
        assert!(rows[0]
            .details_json
            .as_deref()
            .unwrap_or("")
            .contains("mostly_common"));
    }

    #[test]
    fn many_common_domains_is_suppressed() {
        let conn = setup_conn();
        let domains = (0..45)
            .map(|idx| format!("g{}.googlevideo.com", idx))
            .collect::<Vec<_>>();
        insert_queries(&conn, "ip:192.168.1.11", &domains, 2_000);

        let events = evaluate_after_query(
            &conn,
            &queries::DnsQueryRow {
                timestamp_ms: 2_044,
                device_id: Some("ip:192.168.1.11".into()),
                domain: "g44.googlevideo.com".into(),
                query_type: "A".into(),
                action: "allowed".into(),
                upstream_response: None,
                latency_ms: None,
            },
        );

        assert!(events
            .iter()
            .all(|event| event.category != CAT_MANY_DOMAINS));
    }
}
