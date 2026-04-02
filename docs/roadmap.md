# NetSentrix — roadmap

## Done (MVP foundation — current tree)

- Monorepo: `engine/` (Rust), `app/` (SwiftPM), `docs/`, `packaging/macos/`.
- **Config:** TOML load/save; `NETSENTRIX_CONFIG` or default path via `dirs::config_dir()/NetSentrix/config.toml` (see `docs/architecture.md`).
- **SQLite:** WAL, foreign keys, `dns_queries`, `devices`, `alerts`, `rules`, `settings` table; indexes on query time/domain/device_id; **`PRAGMA user_version`** migration runner in `engine/src/storage/migrations.rs` (see `docs/storage-schema.md`).
- **DNS (UDP + TCP):** Same `dns.listen_addr`; single-question parse; allow/block lists + DB rules; sinkhole/NXDOMAIN; forward; **response cache** + metrics; **CNAME chase** on forward path; query log; device upsert from client IP.
- **Control plane:** `dns_paused` in DNS loops (SERVFAIL); **`POST /pause`** (toggle), **`POST /dns/pause`** / **`POST /dns/resume`** (idempotent); **`POST /engine/restart|stop`** documented no-ops (launchctl for real lifecycle).
- **Health:** `dns_udp_bound`, `dns_tcp_bound`, legacy `dns_bound` (= UDP), TCP/UDP last errors; engine **`protection`** object (LAN-capable + distinct clients in window); `sniffer_enabled` always **false** (packet capture not shipped).
- **API:** Axum on loopback; JSON envelope on most routes; flat `GET /health`; Bearer on mutating router; WebSocket **`/ws`** (DNS events).
- **Stats:** `allowed_queries` counts `allowed` + `allowed_cached`; `blocked_queries` counts `blocked` + `blocked_forwarded`.
- **App:** SwiftUI shell; REST + **WebSocket** (Queries + Dashboard sparkline); engine-derived protection in `ProductStatusAdapter` with legacy fallback.

## In progress / next (smaller iterations)

1. **Settings UI parity:** blocklist/allowlist paths, optional pause controls, listen_addr display-only warnings.
2. **DNS edge cases:** multi-question packets; TCP/UDP truncation interop under load (validate in the field).
3. **Packaging:** Harden preflight automation; signed/notarized artifact when ready (no SMJobBless in near term).

## Phase 3+ (deferred)

- **Live packet capture** (libpcap or equivalent) — previously sketched; **removed from Cargo** until a deliberate reimplementation. Event DTOs remain for future use.
- GeoIP/enrich, behavioral rules + alert generation from a real detection pipeline.
- Signed installer / SMJobBless for production port 53.

## Explicitly not planned (near term)

- Cloud sync, remote admin UI, binding API to non-localhost without a security review.
- Copying PacketSniffer code wholesale (reference-only).
