use std::sync::atomic::Ordering;
use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;

use crate::api::models::{
    settings_from_config, ApiEnvelope, DevicePatchBody, HealthResponse, PatternBody,
    ProtectionSummary, SettingsPatch, StatsResponse,
};
use crate::api::protection;
use crate::api::AppState;
use crate::storage::{alerts, devices, queries};

#[derive(Debug, Deserialize)]
pub struct QueriesParams {
    pub limit: Option<u32>,
    pub before_id: Option<i64>,
}

pub async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    let dns = state.dns_state.read().await;
    let eng = state.engine_status.read().await;
    let cfg = state.config.read().await;
    let suggested = crate::system::network::primary_lan_ipv4_string();
    let alerts_total = state
        .db
        .lock()
        .ok()
        .map(|conn| {
            conn.query_row("SELECT COUNT(*) FROM alerts", [], |r| r.get::<_, i64>(0))
                .unwrap_or(0)
        })
        .unwrap_or(0);
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let last_client_query_ms = state
        .db
        .lock()
        .ok()
        .and_then(|conn| queries::latest_timestamp_ms(&conn).ok().flatten());
    let window_ms = (cfg.dns.protection_activity_window_secs.saturating_mul(1000)) as i64;
    let recent_client_activity = last_client_query_ms
        .map(|t| now_ms.saturating_sub(t) < window_ms)
        .unwrap_or(false);
    let dns_listen = cfg.dns.listen_addr.to_string();
    let window_secs = cfg.dns.protection_activity_window_secs;
    let protection = match state.db.lock() {
        Ok(conn) => protection::compute(
            &cfg,
            &dns,
            &eng,
            state.dns_paused.load(Ordering::Relaxed),
            &conn,
            now_ms,
        ),
        Err(_) => ProtectionSummary::db_unavailable(window_secs, dns_listen.clone()),
    };
    Json(HealthResponse {
        ok: true,
        version: env!("CARGO_PKG_VERSION"),
        engine: "netsentrix-engine",
        api_listen: cfg.api.listen_addr.to_string(),
        dns_listen,
        dns_bound: dns.bound,
        dns_last_error: dns.last_error.clone(),
        engine_status: eng.to_api_string(),
        suggested_lan_ip: suggested,
        sniffer_enabled: cfg!(feature = "sniffer"),
        alerts_total,
        api_token_file: crate::api::auth::token_path().display().to_string(),
        last_client_query_ms,
        recent_client_activity,
        dns_paused: state.dns_paused.load(Ordering::Relaxed),
        protection,
    })
}

pub async fn stats(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    let q = match queries::aggregate_stats(&conn) {
        Ok(s) => s,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("sqlite", e.to_string())),
            )
                .into_response();
        }
    };
    let alerts_total: i64 = conn
        .query_row("SELECT COUNT(*) FROM alerts", [], |r| r.get(0))
        .unwrap_or(0);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let day_ago = now - 86_400_000;
    let alerts_last_24h: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM alerts WHERE timestamp > ?1",
            [day_ago],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let blocked_pct = if q.total_queries > 0 {
        (q.blocked_queries as f64 / q.total_queries as f64) * 100.0
    } else {
        0.0
    };
    let (dns_cache_hits, dns_cache_misses) = state.dns_cache.metrics();
    let body = StatsResponse {
        total_queries: q.total_queries,
        blocked_queries: q.blocked_queries,
        allowed_queries: q.allowed_queries,
        blocked_percent: (blocked_pct * 100.0).round() / 100.0,
        distinct_devices: q.distinct_devices,
        alerts_total,
        alerts_last_24h,
        dns_cache_hits,
        dns_cache_misses,
    };
    Json(ApiEnvelope::ok(body)).into_response()
}

pub async fn list_queries(
    State(state): State<Arc<AppState>>,
    Query(q): Query<QueriesParams>,
) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    match queries::list_recent(&conn, q.limit.unwrap_or(50), q.before_id) {
        Ok(rows) => Json(ApiEnvelope::ok(rows)).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response(),
    }
}

pub async fn get_settings(State(state): State<Arc<AppState>>) -> Json<ApiEnvelope<crate::api::models::SettingsResponse>> {
    let cfg = state.config.read().await;
    Json(ApiEnvelope::ok(settings_from_config(&cfg)))
}

pub async fn post_settings(
    State(state): State<Arc<AppState>>,
    Json(patch): Json<SettingsPatch>,
) -> impl IntoResponse {
    let Some(patch_dns) = patch.dns else {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiEnvelope::err("validation", "expected { dns: { ... } }")),
        )
            .into_response();
    };
    {
        let mut cfg = state.config.write().await;
        if let Some(u) = patch_dns.upstream {
            cfg.dns.upstream = u;
        }
        if let Some(p) = patch_dns.blocklist_paths {
            cfg.dns.blocklist_paths = p;
        }
        if let Some(p) = patch_dns.allowlist_paths {
            cfg.dns.allowlist_paths = p;
        }
        if let Some(p) = patch_dns.block_policy {
            cfg.dns.block_policy = p;
        }
        if let Some(w) = patch_dns.protection_activity_window_secs {
            cfg.dns.protection_activity_window_secs = w.clamp(10, 86_400);
        }
        if let Err(e) = crate::config::save(&state.config_path, &cfg) {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("io", e.to_string())),
            )
                .into_response();
        }
    }
    let (allow_paths, block_paths) = {
        let cfg = state.config.read().await;
        (
            cfg.dns.allowlist_paths.clone(),
            cfg.dns.blocklist_paths.clone(),
        )
    };
    {
        let mut f = state.filter.write().await;
        let conn = match state.db.lock() {
            Ok(c) => c,
            Err(_) => {
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
                )
                    .into_response();
            }
        };
        if let Err(e) = f.reload_all(&allow_paths, &block_paths, &conn) {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("filter_reload", e.to_string())),
            )
                .into_response();
        }
    }
    let cfg = state.config.read().await;
    Json(ApiEnvelope::ok(settings_from_config(&cfg))).into_response()
}

pub async fn post_reload(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let new_cfg = match crate::config::load_path(&state.config_path) {
        Ok(c) => c,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("config", e.to_string())),
            )
                .into_response();
        }
    };
    let allow_paths = new_cfg.dns.allowlist_paths.clone();
    let block_paths = new_cfg.dns.blocklist_paths.clone();
    *state.config.write().await = new_cfg;
    {
        let mut f = state.filter.write().await;
        let conn = match state.db.lock() {
            Ok(c) => c,
            Err(_) => {
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
                )
                    .into_response();
            }
        };
        if let Err(e) = f.reload_all(&allow_paths, &block_paths, &conn) {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("filter_reload", e.to_string())),
            )
                .into_response();
        }
    }
    Json(json!({ "ok": true, "data": { "reloaded": true } })).into_response()
}

fn insert_rule(
    conn: &rusqlite::Connection,
    ty: &str,
    pattern: &str,
    action: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO rules (type, pattern, action, enabled) VALUES (?1, ?2, ?3, 1)",
        rusqlite::params![ty, pattern, action],
    )?;
    Ok(())
}

pub async fn post_block(
    State(state): State<Arc<AppState>>,
    Json(body): Json<PatternBody>,
) -> Response {
    let p = body.pattern.trim().to_string();
    if p.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiEnvelope::err("validation", "empty pattern")),
        )
            .into_response();
    }
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    if let Err(e) = insert_rule(&conn, "dns_block", &p, "block") {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response();
    }
    drop(conn);
    let st = state.clone();
    tokio::spawn(async move {
        reload_filter_inner(&st).await;
    });
    Json(json!({ "ok": true, "data": { "pattern": p } })).into_response()
}

pub async fn post_allow_rule(
    State(state): State<Arc<AppState>>,
    Json(body): Json<PatternBody>,
) -> Response {
    let p = body.pattern.trim().to_string();
    if p.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiEnvelope::err("validation", "empty pattern")),
        )
            .into_response();
    }
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    if let Err(e) = insert_rule(&conn, "dns_allow", &p, "allow") {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response();
    }
    drop(conn);
    let st = state.clone();
    tokio::spawn(async move {
        reload_filter_inner(&st).await;
    });
    Json(json!({ "ok": true, "data": { "pattern": p } })).into_response()
}

async fn reload_filter_inner(state: &Arc<AppState>) {
    let (ap, bp) = {
        let cfg = state.config.read().await;
        (
            cfg.dns.allowlist_paths.clone(),
            cfg.dns.blocklist_paths.clone(),
        )
    };
    let mut f = state.filter.write().await;
    let Ok(conn) = state.db.lock() else {
        return;
    };
    if let Err(e) = f.reload_all(&ap, &bp, &conn) {
        tracing::warn!(error = %e, "filter reload after rule");
    }
}

pub async fn list_devices(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    match devices::list_all(&conn) {
        Ok(rows) => Json(ApiEnvelope::ok(rows)).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response(),
    }
}

pub async fn get_device(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    match devices::get(&conn, &id) {
        Ok(Some(d)) => Json(ApiEnvelope::ok(d)).into_response(),
        Ok(None) => (StatusCode::NOT_FOUND, Json(ApiEnvelope::err("not_found", id))).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response(),
    }
}

pub async fn patch_device(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Json(body): Json<DevicePatchBody>,
) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    match devices::set_name(&conn, &id, &body.name) {
        Ok(0) => (StatusCode::NOT_FOUND, Json(ApiEnvelope::err("not_found", id))).into_response(),
        Ok(_) => Json(json!({ "ok": true, "data": { "id": id, "name": body.name } })).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response(),
    }
}

pub async fn list_alerts(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let conn = match state.db.lock() {
        Ok(c) => c,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiEnvelope::err("db_lock", "database mutex poisoned")),
            )
                .into_response();
        }
    };
    match alerts::list_recent(&conn, 200) {
        Ok(rows) => Json(ApiEnvelope::ok(rows)).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiEnvelope::err("sqlite", e.to_string())),
        )
            .into_response(),
    }
}

pub async fn post_pause(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let prev = state.dns_paused.load(Ordering::Relaxed);
    state.dns_paused.store(!prev, Ordering::Relaxed);
    let paused = state.dns_paused.load(Ordering::Relaxed);
    Json(json!({ "ok": true, "data": { "dns_paused": paused } }))
}

pub async fn post_dns_pause(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    state.dns_paused.store(true, Ordering::Relaxed);
    Json(json!({ "ok": true, "data": { "dns_paused": true } }))
}

pub async fn post_dns_resume(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    state.dns_paused.store(false, Ordering::Relaxed);
    Json(json!({ "ok": true, "data": { "dns_paused": false } }))
}

pub async fn post_engine_noop(
    State(_state): State<Arc<AppState>>,
) -> Json<serde_json::Value> {
    Json(json!({ "ok": true, "data": { "note": "Use launchctl for real restart/stop; see docs." } }))
}
