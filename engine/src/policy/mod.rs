//! Advanced policy (Phase 9 v1).
//!
//! - **`dns_time_overrides`** (SQLite migration 3): optional minute-of-day windows in **`chrono::Local`**
//!   that override **`devices.dns_policy`** on the DNS hot path (`devices::resolve_effective_dns_policy`).
//! - Supports overnight windows when `start_min > end_min`.
//! - API: `GET` / `POST` `/policy/time-overrides`, `DELETE` `/policy/time-overrides/:id` (Bearer).
