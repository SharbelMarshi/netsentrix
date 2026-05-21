//! NetSentrix Core — config, storage, API, DNS.

mod alerts;
mod api;
mod config;
mod device;
mod dns;
mod enrich;
mod events;
mod intelligence;
mod policy;
mod rules;
mod sniffer;
mod storage;
mod system;
mod utils;

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use anyhow::Context;
use tokio::sync::RwLock;

use crate::api::AppState;
use crate::dns::cache::ResponseCache;
use crate::dns::filter::DnsFilter;
use crate::dns::server::{DnsLoopShared, DnsRuntimeState};
use crate::events::bus::EventBus;
use crate::system::runtime::EngineStatus;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let config_path = config::resolved_config_path();
    let initial = config::load().context("load config")?;
    tracing::info!(
        config_path = %config_path.display(),
        netsentrix_data_dir = %crate::system::paths::netsentrix_app_dir().display(),
        token_path = %crate::system::paths::token_path().display(),
        db_path = %initial.storage.db_path.display(),
        netsentrix_data_dir_env = ?std::env::var("NETSENTRIX_DATA_DIR").ok(),
        "runtime paths (see engine/src/system/paths.rs for LaunchDaemon vs GUI user notes)"
    );
    let cfg_shared = Arc::new(RwLock::new(initial.clone()));

    let db = storage::db::open(&initial.storage.db_path).context("open database")?;
    storage::migrations::run_migrations(&db).context("run database migrations")?;
    let db_arc = Arc::new(std::sync::Mutex::new(db));

    let mut filter = DnsFilter::default();
    {
        let conn = db_arc.lock().map_err(|e| anyhow::anyhow!("db lock: {e}"))?;
        filter
            .reload_all(
                &initial.dns.allowlist_paths,
                &initial.dns.blocklist_paths,
                &conn,
            )
            .context("load dns filter")?;
    }
    let filter = Arc::new(RwLock::new(filter));

    let bus = Arc::new(EventBus::new());
    let api_token = api::auth::load_or_create_token().context("api token")?;

    let engine_status = Arc::new(RwLock::new(EngineStatus::starting()));
    let dns_state = Arc::new(RwLock::new(DnsRuntimeState::default()));

    let dns_cache = Arc::new(ResponseCache::new());
    let dns_paused = Arc::new(AtomicBool::new(false));
    let dns_shared = Arc::new(DnsLoopShared {
        db: db_arc.clone(),
        filter: filter.clone(),
        config: cfg_shared.clone(),
        bus: bus.clone(),
        cache: dns_cache,
        dns_paused: dns_paused.clone(),
        engine_status: engine_status.clone(),
    });

    let state = Arc::new(AppState {
        config_path,
        config: cfg_shared,
        db: db_arc,
        filter,
        bus,
        engine_status: engine_status.clone(),
        dns_state: dns_state.clone(),
        api_token,
        dns_paused,
        dns_cache: dns_shared.cache.clone(),
    });

    // API and core tasks are up; DNS bind success/failure is reported separately via GET /health
    // (`dns_udp_bound`, `dns_tcp_bound`, `engine_status` may become `error` if UDP bind fails).
    {
        let mut g = engine_status.write().await;
        *g = EngineStatus::running();
    }

    let api_addr = state.config.read().await.api.listen_addr;
    let api_state = state.clone();
    let api_task = tokio::spawn(async move {
        if let Err(e) = api::server::serve(api_addr, api_state).await {
            tracing::error!(error = %e, "API server exited");
        }
    });

    let dns_sh = dns_shared.clone();
    let dns_st = dns_state.clone();
    let dns_task = tokio::spawn(async move {
        if let Err(e) = dns::server::run_dns_loop(dns_sh, dns_st).await {
            tracing::error!(error = %e, "DNS UDP task exited");
        }
    });

    let dns_tcp_sh = dns_shared.clone();
    let dns_tcp_st = dns_state.clone();
    let dns_tcp_task = tokio::spawn(async move {
        if let Err(e) = dns::server::run_dns_tcp_loop(dns_tcp_sh, dns_tcp_st).await {
            tracing::error!(error = %e, "DNS TCP task exited");
        }
    });

    shutdown_signal().await;
    tracing::info!("shutdown signal received");
    api_task.abort();
    dns_task.abort();
    dns_tcp_task.abort();
    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("install CTRL+C listener");
}
