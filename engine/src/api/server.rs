use std::net::SocketAddr;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use axum::middleware::from_fn_with_state;
use axum::routing::{delete, get, patch, post};
use axum::Router;

use crate::api::routes;
use crate::api::websocket;
use crate::config::EngineConfig;
use crate::dns::cache::ResponseCache;
use crate::dns::filter::DnsFilter;
use crate::dns::server::DnsRuntimeState;
use crate::events::bus::EventBus;
use crate::system::runtime::EngineStatus;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct AppState {
    pub config_path: std::path::PathBuf,
    pub config: Arc<RwLock<EngineConfig>>,
    pub db: Arc<std::sync::Mutex<rusqlite::Connection>>,
    pub filter: Arc<RwLock<DnsFilter>>,
    pub bus: Arc<EventBus>,
    pub engine_status: Arc<RwLock<EngineStatus>>,
    pub dns_state: Arc<RwLock<DnsRuntimeState>>,
    pub api_token: String,
    /// When true, DNS loop answers SERVFAIL (UDP/TCP) and does not forward.
    pub dns_paused: Arc<AtomicBool>,
    pub dns_cache: Arc<ResponseCache>,
}

pub async fn serve(addr: SocketAddr, state: Arc<AppState>) -> anyhow::Result<()> {
    let st = state.clone();
    let public = Router::new()
        .route("/health", get(routes::health))
        .route("/stats", get(routes::stats))
        .route("/queries", get(routes::list_queries))
        .route("/settings", get(routes::get_settings))
        .route("/devices", get(routes::list_devices))
        .route("/devices/:id", get(routes::get_device))
        .route("/alerts", get(routes::list_alerts))
        .route("/insights/daily", get(routes::insights_daily))
        .route("/ws", get(websocket::dns_events_ws))
        .with_state(st.clone());

    let authed = Router::new()
        .route("/settings", post(routes::post_settings))
        .route("/reload", post(routes::post_reload))
        .route("/block", post(routes::post_block))
        .route("/allow", post(routes::post_allow_rule))
        .route("/pause", post(routes::post_pause))
        .route("/dns/pause", post(routes::post_dns_pause))
        .route("/dns/resume", post(routes::post_dns_resume))
        .route("/engine/restart", post(routes::post_engine_noop))
        .route("/engine/stop", post(routes::post_engine_noop))
        .route("/devices/:id", patch(routes::patch_device))
        .route(
            "/policy/time-overrides",
            get(routes::list_time_overrides).post(routes::post_time_override),
        )
        .route(
            "/policy/time-overrides/:id",
            delete(routes::delete_time_override),
        )
        .route("/feedback/domain", post(routes::post_domain_feedback))
        .route("/queries/export.csv", get(routes::export_queries_csv))
        .layer(from_fn_with_state(
            st.clone(),
            crate::api::auth::require_bearer_middleware,
        ))
        .with_state(st);

    let app = Router::new().merge(public).merge(authed);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "API listening");
    axum::serve(listener, app).await?;
    Ok(())
}
