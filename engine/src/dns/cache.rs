//! TTL-bounded positive and negative DNS response cache (UDP wire format).

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use crate::config::schema::DnsCacheConfig;

#[derive(Debug, Clone, Hash, PartialEq, Eq)]
struct CacheKey {
    name: String,
    qtype: u16,
}

struct CacheEntry {
    wire: Vec<u8>,
    expires_ms: i64,
}

pub struct ResponseCache {
    inner: Mutex<HashMap<CacheKey, CacheEntry>>,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl ResponseCache {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }

    pub fn metrics(&self) -> (u64, u64) {
        (
            self.hits.load(Ordering::Relaxed),
            self.misses.load(Ordering::Relaxed),
        )
    }

    pub fn get(&self, qname: &str, qtype: u16, now_ms: i64, cfg: &DnsCacheConfig) -> Option<Vec<u8>> {
        if !cfg.enabled {
            return None;
        }
        let key = CacheKey {
            name: normalize_qname(qname),
            qtype,
        };
        let mut g = self.inner.lock().ok()?;
        purge_expired(&mut g, now_ms);
        match g.get(&key) {
            Some(e) if e.expires_ms > now_ms => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(e.wire.clone())
            }
            Some(_) => {
                g.remove(&key);
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    pub fn insert_forwarded(
        &self,
        qname: &str,
        qtype: u16,
        wire: &[u8],
        now_ms: i64,
        cfg: &DnsCacheConfig,
    ) {
        if !cfg.enabled || wire.len() < 12 {
            return;
        }
        let ttl_secs = effective_ttl_secs(wire, cfg);
        let expires_ms = now_ms.saturating_add(ttl_secs.saturating_mul(1000) as i64);
        let key = CacheKey {
            name: normalize_qname(qname),
            qtype,
        };
        let mut g = match self.inner.lock() {
            Ok(x) => x,
            Err(_) => return,
        };
        purge_expired(&mut g, now_ms);
        while g.len() >= cfg.max_entries {
            if let Some(k) = g.keys().next().cloned() {
                g.remove(&k);
            } else {
                break;
            }
        }
        g.insert(
            key,
            CacheEntry {
                wire: wire.to_vec(),
                expires_ms,
            },
        );
    }
}

fn purge_expired(g: &mut HashMap<CacheKey, CacheEntry>, now_ms: i64) {
    g.retain(|_, e| e.expires_ms > now_ms);
}

fn normalize_qname(s: &str) -> String {
    s.trim().trim_end_matches('.').to_lowercase()
}

/// Derive cache TTL from the first answer RR when possible; NXDOMAIN / failure uses negative TTL cap.
fn effective_ttl_secs(wire: &[u8], cfg: &DnsCacheConfig) -> u32 {
    let rcode = (wire[3] & 0x0f) as u32;
    if rcode == 3 {
        // NXDOMAIN — negative cache
        return cfg.negative_ttl_secs.clamp(1, 86_400);
    }
    if rcode != 0 {
        // Other errors: short cache to avoid hammering
        return cfg.min_ttl_secs.max(5).min(cfg.negative_ttl_secs);
    }
    let ancount = u16::from_be_bytes([wire[6], wire[7]]) as usize;
    let qdcount = u16::from_be_bytes([wire[4], wire[5]]) as usize;
    if ancount == 0 {
        return cfg.default_positive_ttl_secs.clamp(cfg.min_ttl_secs, cfg.max_ttl_secs);
    }
    let Some(mut pos) = skip_questions(wire, 12, qdcount) else {
        return cfg.default_positive_ttl_secs.clamp(cfg.min_ttl_secs, cfg.max_ttl_secs);
    };
    // First answer RR: NAME TYPE(2) CLASS(2) TTL(4) RDLEN(2) RDATA
    let Some(next) = skip_name(wire, pos) else {
        return cfg.default_positive_ttl_secs.clamp(cfg.min_ttl_secs, cfg.max_ttl_secs);
    };
    pos = next;
    if pos + 10 > wire.len() {
        return cfg.default_positive_ttl_secs.clamp(cfg.min_ttl_secs, cfg.max_ttl_secs);
    }
    let ttl = u32::from_be_bytes([
        wire[pos + 4],
        wire[pos + 5],
        wire[pos + 6],
        wire[pos + 7],
    ]);
    ttl.clamp(cfg.min_ttl_secs, cfg.max_ttl_secs)
}

fn skip_questions(buf: &[u8], mut pos: usize, qdcount: usize) -> Option<usize> {
    for _ in 0..qdcount {
        pos = skip_name(buf, pos)?;
        if pos + 4 > buf.len() {
            return None;
        }
        pos += 4;
    }
    Some(pos)
}

fn skip_name(buf: &[u8], mut pos: usize) -> Option<usize> {
    loop {
        if pos >= buf.len() {
            return None;
        }
        let len = buf[pos] as usize;
        if len == 0 {
            return Some(pos + 1);
        }
        if (buf[pos] & 0xc0) == 0xc0 {
            return Some(pos + 2);
        }
        if len > 63 || pos + 1 + len > buf.len() {
            return None;
        }
        pos += 1 + len;
    }
}
