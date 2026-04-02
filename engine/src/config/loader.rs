//! Load and persist `config.toml`.
//!
//! - **Path:** `NETSENTRIX_CONFIG` or [`crate::system::paths::default_config_file`].
//! - **First run:** Writes defaults (including `storage.db_path` from [`crate::system::paths::default_db_path`],
//!   which respects `NETSENTRIX_DATA_DIR` if set). See `system/paths.rs` for the full runtime model.

use std::path::{Path, PathBuf};

use anyhow::Context;

use crate::config::defaults;
use crate::config::schema::EngineConfig;
use crate::system::paths;

/// Active config file path (`NETSENTRIX_CONFIG` or default).
pub fn resolved_config_path() -> PathBuf {
    std::env::var("NETSENTRIX_CONFIG")
        .map(PathBuf::from)
        .unwrap_or_else(|_| default_config_path())
}

/// Load TOML from `NETSENTRIX_CONFIG` or the default platform path; write defaults if missing.
pub fn load() -> anyhow::Result<EngineConfig> {
    let path = resolved_config_path();
    if path.exists() {
        load_path(&path)
    } else {
        let cfg = defaults::engine_config();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).with_context(|| parent.display().to_string())?;
        }
        let text = toml::to_string_pretty(&cfg).context("serialize default config")?;
        std::fs::write(&path, text).with_context(|| path.display().to_string())?;
        tracing::info!(path = %path.display(), "wrote default config");
        Ok(cfg)
    }
}

/// Parse existing TOML (e.g. `POST /reload`).
pub fn load_path(path: &Path) -> anyhow::Result<EngineConfig> {
    let text = std::fs::read_to_string(path).with_context(|| path.display().to_string())?;
    toml::from_str(&text).context("parse config TOML")
}

fn default_config_path() -> PathBuf {
    paths::default_config_file()
}

/// Persist full config to TOML (e.g. after `/settings` POST).
pub fn save(path: &std::path::Path, cfg: &EngineConfig) -> anyhow::Result<()> {
    let text = toml::to_string_pretty(cfg).context("serialize config")?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).with_context(|| parent.display().to_string())?;
    }
    std::fs::write(path, text).with_context(|| path.display().to_string())?;
    Ok(())
}
