use std::net::{Ipv4Addr, SocketAddr};

use crate::config::schema::{ApiSection, DnsCacheConfig, DnsSection, EngineConfig, StorageSection};
use crate::system::paths;

pub fn engine_config() -> EngineConfig {
    EngineConfig {
        api: ApiSection {
            listen_addr: SocketAddr::from((Ipv4Addr::LOCALHOST, 8756)),
        },
        dns: DnsSection {
            listen_addr: SocketAddr::from((Ipv4Addr::LOCALHOST, 5353)),
            upstream: "8.8.8.8:53".into(),
            blocklist_paths: Vec::new(),
            allowlist_paths: Vec::new(),
            block_policy: crate::config::schema::BlockPolicy::AZero,
            cache: DnsCacheConfig::default(),
            protection_activity_window_secs: 300,
        },
        storage: StorageSection {
            db_path: paths::default_db_path(),
        },
    }
}
