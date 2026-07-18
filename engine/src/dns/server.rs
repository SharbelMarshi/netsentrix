//! UDP/TCP DNS: parse, filter, respond or forward upstream; log + events.

use std::net::Ipv4Addr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::{RwLock, Semaphore};
use tokio::time::sleep;

use crate::config::schema::{BlockPolicy, EngineConfig};
use crate::dns::cache::ResponseCache;
use crate::dns::filter::{DnsFilter, FilterDecision};
use crate::dns::parser::parse_first_question;
use crate::dns::responder;
use crate::dns::upstream;
use crate::events::bus::EventBus;
use crate::events::models::DnsQueryEvent;
use crate::device::{client_key, manager};
use crate::sniffer::models::DetectionEvent;
use crate::storage::devices;
use crate::storage::queries::{self, DnsQueryRow};

#[derive(Debug, Default, Clone)]
pub struct DnsRuntimeState {
    /// UDP DNS socket successfully bound (`dns.listen_addr`).
    pub udp_bound: bool,
    /// TCP DNS listener successfully bound (same address/port).
    pub tcp_bound: bool,
    /// Last UDP bind failure message (cleared when UDP bind succeeds).
    pub udp_last_error: Option<String>,
    /// Last TCP bind failure message (cleared when TCP bind succeeds).
    pub tcp_last_error: Option<String>,
}

pub struct DnsLoopShared {
    pub db: Arc<std::sync::Mutex<rusqlite::Connection>>,
    pub filter: Arc<RwLock<DnsFilter>>,
    pub config: Arc<RwLock<EngineConfig>>,
    pub bus: Arc<EventBus>,
    pub cache: Arc<ResponseCache>,
    pub dns_paused: Arc<AtomicBool>,
    pub engine_status: Arc<RwLock<crate::system::runtime::EngineStatus>>,
}

pub async fn run_dns_loop(
    shared: Arc<DnsLoopShared>,
    runtime: Arc<RwLock<DnsRuntimeState>>,
) -> anyhow::Result<()> {
    let listen_addr = { shared.config.read().await.dns.listen_addr };

    let socket = match UdpSocket::bind(listen_addr).await {
        Ok(s) => s,
        Err(e) => {
            {
                let mut g = runtime.write().await;
                g.udp_bound = false;
                g.udp_last_error = Some(e.to_string());
            }
            {
                let mut s = shared.engine_status.write().await;
                *s = crate::system::runtime::EngineStatus::error();
            }
            tracing::warn!(
                error = %e,
                %listen_addr,
                "DNS UDP bind failed; engine_status=error; idle until restart/reload (see GET /health dns_last_error)"
            );
            loop {
                sleep(Duration::from_secs(86_400)).await;
            }
        }
    };

    {
        let mut g = runtime.write().await;
        g.udp_bound = true;
        g.udp_last_error = None;
    }
    tracing::info!(%listen_addr, "DNS UDP listening");

    let upstream_sock = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).await?;
    let mut buf = [0u8; 1232];
    let mut up_buf = [0u8; 1232];

    loop {
        let (n, src) = match socket.recv_from(&mut buf).await {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!(error = %e, "DNS recv error");
                continue;
            }
        };

        let req = &buf[..n];
        let now_ms = now_millis();
        let device_id = client_key(&src);

        if shared.dns_paused.load(Ordering::Relaxed) {
            if let Some(sf) = responder::build_servfail(req) {
                let _ = socket.send_to(&sf, src).await;
            }
            continue;
        }

        if let Some((resp, row)) =
            resolve_dns_datagram(&shared, req, now_ms, &device_id, &upstream_sock, &mut up_buf).await
        {
            let _ = socket.send_to(&resp, src).await;
            if let Some(r) = row {
                spawn_log(&shared, r);
            }
        }
    }
}

pub async fn run_dns_tcp_loop(
    shared: Arc<DnsLoopShared>,
    runtime: Arc<RwLock<DnsRuntimeState>>,
) -> anyhow::Result<()> {
    let listen_addr = { shared.config.read().await.dns.listen_addr };
    let listener = match TcpListener::bind(listen_addr).await {
        Ok(l) => l,
        Err(e) => {
            {
                let mut g = runtime.write().await;
                g.tcp_bound = false;
                g.tcp_last_error = Some(e.to_string());
            }
            tracing::warn!(
                error = %e,
                %listen_addr,
                "DNS TCP bind failed; idling (UDP may still work; engine_status unchanged; check dns_tcp_bound on /health)"
            );
            loop {
                sleep(Duration::from_secs(86_400)).await;
            }
        }
    };
    {
        let mut g = runtime.write().await;
        g.tcp_bound = true;
        g.tcp_last_error = None;
    }
    tracing::info!(%listen_addr, "DNS TCP listening");

    let concurrency = Arc::new(Semaphore::new(64));
    let conn_timeout = Duration::from_secs(30);

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(x) => x,
            Err(e) => {
                tracing::warn!(error = %e, "DNS TCP accept");
                continue;
            }
        };
        let permit = match concurrency.clone().acquire_owned().await {
            Ok(p) => p,
            Err(_) => continue,
        };
        let sh = shared.clone();
        tokio::spawn(async move {
            let _permit = permit;
            let r = tokio::time::timeout(conn_timeout, handle_dns_tcp_connection(sh, stream, peer)).await;
            match r {
                Ok(Ok(())) => {}
                Ok(Err(e)) => tracing::debug!(error = %e, "DNS TCP connection"),
                Err(_) => tracing::debug!("DNS TCP connection timed out"),
            }
        });
    }
}

async fn handle_dns_tcp_connection(
    shared: Arc<DnsLoopShared>,
    mut stream: TcpStream,
    peer: std::net::SocketAddr,
) -> anyhow::Result<()> {
    let len = stream.read_u16().await? as usize;
    if len == 0 || len > 4096 {
        return Ok(());
    }
    let mut req = vec![0u8; len];
    stream.read_exact(&mut req).await?;

    let upstream_sock = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).await?;
    let mut up_buf = [0u8; 1232];
    let now_ms = now_millis();
    let device_id = format!("ip:{}", peer.ip());

    if shared.dns_paused.load(Ordering::Relaxed) {
        if let Some(sf) = responder::build_servfail(&req) {
            let blen = sf.len().min(u16::MAX as usize) as u16;
            stream.write_u16(blen).await?;
            stream.write_all(&sf[..blen as usize]).await?;
        }
        return Ok(());
    }

    if let Some((resp, row)) = resolve_dns_datagram(
        &shared,
        &req,
        now_ms,
        &device_id,
        &upstream_sock,
        &mut up_buf,
    )
    .await
    {
        let blen = resp.len().min(u16::MAX as usize) as u16;
        stream.write_u16(blen).await?;
        stream.write_all(&resp[..blen as usize]).await?;
        if let Some(r) = row {
            spawn_log(&shared, r);
        }
    }
    Ok(())
}

/// Returns response bytes and optional row to persist (TCP uses placeholder device_id for logging).
async fn resolve_dns_datagram(
    shared: &DnsLoopShared,
    req: &[u8],
    now_ms: i64,
    device_id: &str,
    upstream_sock: &UdpSocket,
    up_buf: &mut [u8],
) -> Option<(Vec<u8>, Option<DnsQueryRow>)> {
    let pq = parse_first_question(req)?;

    let (policy, upstream_addr, cache_cfg) = {
        let cfg = shared.config.read().await;
        let addr = upstream::parse_upstream(&cfg.dns.upstream).ok()?;
        (cfg.dns.block_policy, addr, cfg.dns.cache.clone())
    };

    let qtype_str = qtype_label(pq.qtype);

    let explicitly_allowed = {
        let filter = shared.filter.read().await;
        filter.explicitly_allowlisted(&pq.qname)
    };

    if explicitly_allowed {
        return forward_allow_resolve(
            shared,
            &pq,
            req,
            now_ms,
            device_id,
            upstream_sock,
            upstream_addr,
            up_buf,
            &cache_cfg,
            &qtype_str,
        )
        .await;
    }

    let device_policy = match shared.db.lock() {
        Ok(c) => devices::resolve_effective_dns_policy(&c, device_id),
        Err(_) => "normal".to_string(),
    };

    match device_policy.as_str() {
        "blocked" => {
            let resp = responder::build_blocked_response(req, &pq, policy).or_else(|| {
                responder::build_blocked_response(req, &pq, BlockPolicy::NxDomain)
            });
            if let Some(bytes) = resp {
                return Some((
                    bytes,
                    Some(DnsQueryRow {
                        timestamp_ms: now_ms,
                        device_id: Some(device_id.to_string()),
                        domain: pq.qname.clone(),
                        query_type: qtype_str.clone(),
                        action: "blocked_device".into(),
                        upstream_response: Some("device_blocked".into()),
                        latency_ms: Some(0),
                    }),
                ));
            }
            return None;
        }
        "paused" => {
            if let Some(sf) = responder::build_servfail(req) {
                return Some((
                    sf,
                    Some(DnsQueryRow {
                        timestamp_ms: now_ms,
                        device_id: Some(device_id.to_string()),
                        domain: pq.qname.clone(),
                        query_type: qtype_str.clone(),
                        action: "device_paused_dns".into(),
                        upstream_response: Some("device_paused".into()),
                        latency_ms: Some(0),
                    }),
                ));
            }
            return None;
        }
        "restricted" => {
            let resp = responder::build_blocked_response(req, &pq, policy).or_else(|| {
                responder::build_blocked_response(req, &pq, BlockPolicy::NxDomain)
            });
            if let Some(bytes) = resp {
                return Some((
                    bytes,
                    Some(DnsQueryRow {
                        timestamp_ms: now_ms,
                        device_id: Some(device_id.to_string()),
                        domain: pq.qname.clone(),
                        query_type: qtype_str.clone(),
                        action: "blocked_restricted".into(),
                        upstream_response: Some("restricted_allowlist".into()),
                        latency_ms: Some(0),
                    }),
                ));
            }
            return None;
        }
        _ => {}
    }

    let decision = {
        let filter = shared.filter.read().await;
        filter.decision(&pq.qname)
    };

    match decision {
        FilterDecision::Block => {
            let resp = responder::build_blocked_response(req, &pq, policy).or_else(|| {
                responder::build_blocked_response(req, &pq, BlockPolicy::NxDomain)
            });

            if let Some(bytes) = resp {
                return Some((
                    bytes,
                    Some(DnsQueryRow {
                        timestamp_ms: now_ms,
                        device_id: Some(device_id.to_string()),
                        domain: pq.qname.clone(),
                        query_type: qtype_str.clone(),
                        action: "blocked".into(),
                        upstream_response: Some(match policy {
                            BlockPolicy::AZero => "sinkhole".into(),
                            BlockPolicy::NxDomain => "nxdomain".into(),
                        }),
                        latency_ms: Some(0),
                    }),
                ));
            }
            if let Some(len) = forward_query(req, upstream_sock, upstream_addr, up_buf).await {
                let b = up_buf[..len].to_vec();
                return Some((
                    b,
                    Some(DnsQueryRow {
                        timestamp_ms: now_ms,
                        device_id: Some(device_id.to_string()),
                        domain: pq.qname.clone(),
                        query_type: qtype_str,
                        action: "blocked_forwarded".into(),
                        upstream_response: Some("upstream".into()),
                        latency_ms: None,
                    }),
                ));
            }
            None
        }
        FilterDecision::Allow => {
            forward_allow_resolve(
                shared,
                &pq,
                req,
                now_ms,
                device_id,
                upstream_sock,
                upstream_addr,
                up_buf,
                &cache_cfg,
                &qtype_str,
            )
            .await
        }
    }
}

fn build_outbound_query(id: u16, qname: &str, qtype: u16, qclass: u16) -> Option<Vec<u8>> {
    let mut v = Vec::with_capacity(64);
    v.extend_from_slice(&id.to_be_bytes());
    v.extend_from_slice(&0x0100u16.to_be_bytes());
    v.extend_from_slice(&1u16.to_be_bytes());
    v.extend_from_slice(&0u16.to_be_bytes());
    v.extend_from_slice(&0u16.to_be_bytes());
    v.extend_from_slice(&0u16.to_be_bytes());
    for label in qname.trim().trim_end_matches('.').split('.') {
        if label.is_empty() {
            continue;
        }
        let b = label.as_bytes();
        if b.len() > 63 {
            return None;
        }
        v.push(b.len() as u8);
        v.extend_from_slice(b);
    }
    v.push(0);
    v.extend_from_slice(&qtype.to_be_bytes());
    v.extend_from_slice(&qclass.to_be_bytes());
    Some(v)
}

/// Forward allowed queries with bounded CNAME chasing (A/AAAA).
#[allow(clippy::too_many_arguments)]
async fn forward_allow_resolve(
    shared: &DnsLoopShared,
    pq: &crate::dns::parser::ParsedQuestion,
    _req: &[u8],
    now_ms: i64,
    device_id: &str,
    upstream_sock: &UdpSocket,
    upstream_addr: std::net::SocketAddr,
    up_buf: &mut [u8],
    cache_cfg: &crate::config::schema::DnsCacheConfig,
    qtype_str: &str,
) -> Option<(Vec<u8>, Option<DnsQueryRow>)> {
    if let Some(cached) = shared.cache.get(&pq.qname, pq.qtype, now_ms, cache_cfg) {
        return Some((
            cached,
            Some(DnsQueryRow {
                timestamp_ms: now_ms,
                device_id: Some(device_id.to_string()),
                domain: pq.qname.clone(),
                query_type: qtype_str.to_string(),
                action: "allowed_cached".into(),
                upstream_response: Some("cache".into()),
                latency_ms: Some(0),
            }),
        ));
    }

    const MAX_CNAME: usize = 8;
    let start = Instant::now();
    let mut visited = std::collections::HashSet::<String>::new();
    let mut name = pq.qname.clone();
    let mut last_resp: Option<Vec<u8>> = None;

    for _ in 0..MAX_CNAME {
        let nk = name.trim().trim_end_matches('.').to_ascii_lowercase();
        if !visited.insert(nk) {
            tracing::debug!(%name, "cname chase: loop detected");
            break;
        }
        let qwire = build_outbound_query(pq.id, &name, pq.qtype, pq.qclass)?;
        let len = forward_query(&qwire, upstream_sock, upstream_addr, up_buf).await?;
        let resp = up_buf[..len].to_vec();
        last_resp = Some(resp.clone());

        if let Some(next) = crate::dns::response::cname_next_query_name(&resp, &name, pq.qtype) {
            name = next;
            continue;
        }

        let lat = start.elapsed().as_millis() as i64;
        shared
            .cache
            .insert_forwarded(&pq.qname, pq.qtype, &resp, now_ms, cache_cfg);
        return Some((
            resp,
            Some(DnsQueryRow {
                timestamp_ms: now_ms,
                device_id: Some(device_id.to_string()),
                domain: pq.qname.clone(),
                query_type: qtype_str.to_string(),
                action: "allowed".into(),
                upstream_response: Some("upstream".into()),
                latency_ms: Some(lat),
            }),
        ));
    }

    if let Some(resp) = last_resp {
        let lat = start.elapsed().as_millis() as i64;
        shared
            .cache
            .insert_forwarded(&pq.qname, pq.qtype, &resp, now_ms, cache_cfg);
        return Some((
            resp,
            Some(DnsQueryRow {
                timestamp_ms: now_ms,
                device_id: Some(device_id.to_string()),
                domain: pq.qname.clone(),
                query_type: qtype_str.to_string(),
                action: "allowed".into(),
                upstream_response: Some("upstream".into()),
                latency_ms: Some(lat),
            }),
        ));
    }
    None
}

async fn forward_query(
    req: &[u8],
    up_sock: &UdpSocket,
    upstream: std::net::SocketAddr,
    up_buf: &mut [u8],
) -> Option<usize> {
    if up_sock.send_to(req, upstream).await.is_err() {
        return None;
    }
    match tokio::time::timeout(Duration::from_secs(5), up_sock.recv_from(up_buf)).await {
        Ok(Ok((n, _))) => Some(n),
        Ok(Err(e)) => {
            tracing::warn!(error = %e, "upstream recv");
            None
        }
        Err(_) => {
            tracing::warn!("upstream timeout");
            None
        }
    }
}

fn spawn_log(shared: &DnsLoopShared, row: DnsQueryRow) {
    let db = shared.db.clone();
    let bus = shared.bus.clone();
    let ev = DnsQueryEvent {
        domain: row.domain.clone(),
        client_ip: row
            .device_id
            .as_ref()
            .and_then(|s| s.strip_prefix("ip:"))
            .unwrap_or("")
            .to_string(),
        action: row.action.clone(),
    };
    tokio::task::spawn(async move {
        let row2 = row.clone();
        let ev2 = ev.clone();
        let db2 = db.clone();
        let j = tokio::task::spawn_blocking(move || -> Vec<DetectionEvent> {
            let Ok(conn) = db2.lock() else {
                tracing::warn!("db mutex poisoned");
                return Vec::new();
            };
            if let Err(e) = queries::insert(&conn, &row2) {
                tracing::warn!(error = %e, "insert dns_queries");
                return Vec::new();
            }
            if let Some(ref did) = row2.device_id {
                if did.starts_with("ip:") {
                    manager::touch_seen(&conn, did, row2.timestamp_ms);
                }
            }
            crate::alerts::evaluate_after_query(&conn, &row2)
        })
        .await;
        let detection_events = match j {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!(error = %e, "log task join failed");
                Vec::new()
            }
        };
        bus.publish_dns(ev2);
        for ev in detection_events {
            bus.publish_alert_triggered(ev);
        }
    });
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn qtype_label(qtype: u16) -> String {
    match qtype {
        1 => "A".into(),
        28 => "AAAA".into(),
        5 => "CNAME".into(),
        15 => "MX".into(),
        16 => "TXT".into(),
        n => format!("TYPE{n}"),
    }
}
