# NetSentrix — roadmap

## Phases 2.6–4 (execution)

- **Phase 2.6:** UI stability first (Queries `Table` + WebSocket + poll, selection, navigation from Alerts), then alert UX polish. Do not chase AppKit console noise without a reproducible bug (`docs/notes/queries-ui-debug.md`).
- **Phase 3:** Per-device **control surface** in-app: list + detail show **saved vs effective** DNS mode (`dns_policy`, `effective_dns_policy`, `schedule_override_active` on `GET /devices` / `GET /devices/:id`), row/context actions and confirmations for disruptive modes, `PATCH /devices/:id` for renames/tags/mode. Precedence: `docs/architecture.md`.
- **Phase 4:** **Audit** (`docs/notes/settings-parity-audit.md`) → **UI** (parity, runtime transparency from `GET /health`) → **docs sync**.

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

1. **DNS edge cases:** multi-question packets; TCP/UDP truncation interop under load (validate in the field).
2. **Packaging:** Signed/notarized artifact when ready (no SMJobBless in near term); preflight gains more checks over time.

## Recently landed (core roadmap slices)

- **Settings / operator:** App edits **blocklist** and **allowlist** paths via `POST /settings`; read-only **loopback DNS listen** warning; Queries table prunes stale selection on refresh; **CSV export** of recent queries (`GET /queries/export.csv` + Settings button).
- **Health automation:** `GET /health` includes **`setup_hints`** (actionable copy + optional `suggested_fix`) from protection signals, IPv6-on-host hint, and DNS-visible DoH-style hostname heuristics — **honest scope**, not bypass proof.
- **Alerts / intelligence:** `GET /alerts` **`priority`** tiers; alert **`details_json`** may include **`intel_signals`** (rule-trace strings); classifier honors **`domain_feedback`** (`POST /feedback/domain`); right-click hints in the app.
- **Insights (FG2):** `GET /insights/daily` + Dashboard **Charts** card (top domains / devices, peak hour).
- **Phase 9 v1:** SQLite **`dns_time_overrides`** + **`devices.tags`**; **`resolve_effective_dns_policy`** applies local time windows; CRUD **`/policy/time-overrides`**; device tags on **`PATCH /devices/:id`**.
- **Enrichment (Phase 8 slice):** Deterministic **`explain_domain`** surfaced on insights rows (`engine/src/enrich/mod.rs` re-export).
- **Sniffer gate:** Cargo feature **`sniffer_capture`** reserved; `sniffer_enabled` stays **false** until a real capture loop exists — see `docs/sniffer-permissions.md`.
- **Packaging:** `packaging/macos/MAC_MINI_APPLIANCE.md` operator checklist.

## Phase 3+ (deferred)

- **Live packet capture** (libpcap or equivalent) — optional **`sniffer_capture`** feature flag only; no live loop yet. Event DTOs + `EventBus` channels remain for Phase 6+.
- Deeper GeoIP/ASN/rDNS usage from `enrich/` modules; behavioral rules + richer alert correlation.
- Signed installer / SMJobBless for production port 53.

## Explicitly not planned (near term)

- Cloud sync, remote admin UI, binding API to non-localhost without a security review.
- Copying PacketSniffer code wholesale (reference-only).
