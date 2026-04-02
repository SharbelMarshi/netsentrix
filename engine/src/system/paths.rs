//! Resolved filesystem locations (config dir, data dir).

use std::path::PathBuf;

/// Same default as `config::loader`: `dirs::config_dir()/NetSentrix/config.toml`.
pub fn default_config_file() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("NetSentrix")
        .join("config.toml")
}
