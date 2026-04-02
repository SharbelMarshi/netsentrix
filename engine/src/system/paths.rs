//! Filesystem layout for NetSentrix Core.
//!
//! # Supported MVP runtime model (Mac mini, always-on)
//!
//! - **Engine:** Runs as a **system LaunchDaemon** (typically **root**) so it can bind **UDP/TCP :53**
//!   when `dns.listen_addr` uses port 53.
//! - **App:** Runs as the **logged-in GUI user** and calls `http://127.0.0.1:<api_port>` with the
//!   Bearer token read from disk.
//!
//! ## Where things live
//!
//! | Item | Resolution |
//! |------|------------|
//! | Config file | `NETSENTRIX_CONFIG` if set, else `dirs::config_dir()/NetSentrix/config.toml`. |
//! | Per-user “NetSentrix” data directory | `NETSENTRIX_DATA_DIR/NetSentrix` if `NETSENTRIX_DATA_DIR` is set, else `dirs::data_dir()/NetSentrix`. |
//! | API token | **`NETSENTRIX_TOKEN_FILE`** if set (absolute path), else `netsentrix_app_dir()/api.token` |
//! | Default DB path (in generated config) | `netsentrix_app_dir()/engine.db` — override with `storage.db_path` in TOML. |
//!
//! ## Root vs GUI user (critical for the app)
//!
//! With **no** env overrides, a LaunchDaemon running as **root** resolves `dirs::data_dir()` to
//! **`/var/root/Library/Application Support`** — so the token is under **`/var/root/.../NetSentrix/`**,
//! while the menu bar app reads **`~/Library/Application Support/NetSentrix/api.token`** for the GUI user.
//! Those are **different files**. For a working appliance, either:
//!
//! - Set **`NETSENTRIX_DATA_DIR`** in the plist to a **shared** directory (e.g. `/usr/local/var/netsentrix`)
//!   with permissions that allow the engine (root) to write and the GUI user to read the token; **and**
//!   set **`storage.db_path`** in config to a path under that tree (or same policy), **or**
//! - Run the engine as the same user as the desktop (LaunchAgent — then port 53 usually **cannot** bind).
//!
//! Logs from launchd: see `StandardOutPath` / `StandardErrorPath` in the plist (`/var/log/netsentrix-engine*.log`).

use std::path::PathBuf;

/// Optional override: directory whose **`NetSentrix/`** subtree holds the token and default DB layout.
///
/// Example plist: `NETSENTRIX_DATA_DIR` = `/usr/local/var/netsentrix` → token at
/// `/usr/local/var/netsentrix/NetSentrix/api.token`.
pub fn netsentrix_data_root() -> PathBuf {
    std::env::var("NETSENTRIX_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| dirs::data_dir().unwrap_or_else(|| PathBuf::from(".")))
}

/// `NETSENTRIX_DATA_DIR/NetSentrix` or `dirs::data_dir()/NetSentrix`.
pub fn netsentrix_app_dir() -> PathBuf {
    netsentrix_data_root().join("NetSentrix")
}

/// Same as `config::loader` default: `dirs::config_dir()/NetSentrix/config.toml` (not under `NETSENTRIX_DATA_DIR`).
pub fn default_config_file() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("NetSentrix")
        .join("config.toml")
}

/// API Bearer token file (`load_or_create_token` in `api::auth`).
pub fn token_path() -> PathBuf {
    if let Ok(p) = std::env::var("NETSENTRIX_TOKEN_FILE") {
        return PathBuf::from(p);
    }
    netsentrix_app_dir().join("api.token")
}

/// Default SQLite path used when writing a fresh default `config.toml`.
pub fn default_db_path() -> PathBuf {
    netsentrix_app_dir().join("engine.db")
}
