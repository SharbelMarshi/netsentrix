//! Packet capture / live traffic analysis — **not part of the shipping MVP**.
//!
//! Event DTOs are shared with [`crate::events::bus`]. Optional work is gated behind the
//! **`sniffer_capture`** Cargo feature (see `Cargo.toml`); `GET /health` **`sniffer_enabled`**
//! remains **`false`** until a verified capture loop is implemented.
//!
//! Permissions and platform notes: `docs/sniffer-permissions.md` (repo root).

pub mod models;

/// `true` only when live capture is running and verified (Phase 6+).
pub fn sniffer_enabled_for_health() -> bool {
    let _reserved = cfg!(feature = "sniffer_capture");
    false
}
