//! Packet capture / live traffic analysis — **not part of the shipping MVP**.
//!
//! Libpcap-based capture was never completed and is **quarantined** (see `Cargo.toml`: no
//! `sniffer` feature). This module only exposes **event DTOs** shared with [`crate::events::bus`]
//! for future phases. Do not add capture dependencies here without a deliberate product decision.

pub mod models;
