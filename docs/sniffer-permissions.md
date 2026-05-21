# Sniffer / packet capture — permissions (Phase 6+)

NetSentrix does **not** ship a live capture loop in default builds. Optional integration is reserved behind the engine Cargo feature **`sniffer_capture`** (see `engine/Cargo.toml`).

When capture is implemented:

- **macOS:** Live capture typically requires **full disk access** or **developer tools** privileges depending on the API used, and often **root** or a dedicated helper for `BPF` devices. Document the exact entitlement model before enabling product UI.
- **Operator trust:** `GET /health` field **`sniffer_enabled`** must be **`true`** only when frames are actually being processed — not merely because a feature flag compiled in.
- **Privacy:** Capture is **local-only**; do not exfiltrate payloads. Prefer metadata (IPs, ports, sizes) consistent with `engine/src/sniffer/models.rs` `PacketEvent`.

Until then, event DTOs and the `EventBus` packet channel remain **infrastructure only**.
