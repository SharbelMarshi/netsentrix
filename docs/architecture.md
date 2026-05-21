# NetSentrix — architecture

## Separation

- **Engine (NetSentrix Core):** DNS, persistence, localhost JSON API + WebSocket. **Packet capture is not part of the MVP** (no libpcap feature; `sniffer` module holds DTOs only).
- **App:** SwiftUI product UI; talks to the engine over HTTP/WebSocket on loopback only.

## Processes

- One long-running **engine** process on the always-on Mac (production: **system `launchd`** as **root** for port 53; see `packaging/macos/launchd/` and `packaging/macos/installer/BUILD.md`).
- **App** runs as the **logged-in GUI user** and uses `http://127.0.0.1:<api_port>` (default **8756** in the generated template). The engine exposes WebSocket `GET /ws`; the macOS app uses REST plus a WebSocket client for live DNS events where enabled.

## Configuration

- **Config file:** If **`NETSENTRIX_CONFIG`** is set, that path is used. Otherwise: **`dirs::config_dir()/NetSentrix/config.toml`** (on macOS under the *running user’s* Application Support — for root daemons that is **`/var/root/Library/Application Support/...`**). See `engine/src/system/paths.rs` and `config/loader.rs`.
- **Format:** TOML (`engine/src/config/schema.rs`): `api.listen_addr`, `dns.*`, `storage.db_path`.
- **Defaults:** Dev-friendly DNS bind is often **not** `:53` (e.g. `127.0.0.1:5353`); production on a LAN DNS role uses **`0.0.0.0:53`** or similar with appropriate privileges.

## Data

- **`NETSENTRIX_DATA_DIR` (optional):** If set, the engine uses **`$NETSENTRIX_DATA_DIR/NetSentrix/`** for the default **`api.token`** location and default **`engine.db`** path in newly written config. **`NETSENTRIX_TOKEN_FILE`** (optional) overrides the token path only. If unset, behavior falls back to **`dirs::data_dir()/NetSentrix/`** for the process user (see module docs in `engine/src/system/paths.rs`).
- **SQLite** at `storage.db_path` from config. Tables: devices, dns_queries, alerts, rules, settings — see `docs/storage-schema.md`.
- **Schema:** `storage::migrations::run_migrations` runs after open; **`PRAGMA user_version`** tracks applied steps; WAL and foreign keys are set in migration 1. See `engine/src/storage/migrations.rs`.

## DNS policy precedence (per client)

Order used when answering a query for a given `device_id` (see `engine/src/dns/server.rs` and `engine/src/storage/devices.rs`):

1. **Pause (global):** If `dns_paused` is set, the engine answers SERVFAIL and does not forward (see control plane below).
2. **Per-device effective DNS policy:** `devices.dns_policy` (`normal` \| `restricted` \| `paused` \| `blocked`), then optional **time-of-day** row from `dns_time_overrides` that matches local wall time and scope (`resolve_effective_dns_policy`). **`GET /devices`** and **`GET /devices/:id`** expose both the stored `dns_policy` and **`effective_dns_policy`** plus **`schedule_override_active`** so the app can show “saved vs now” without re-implementing precedence in Swift.
3. **Domain rules:** Global allow/block lists and DB rules in the DNS filter (`engine/src/dns/filter.rs`). **Allowlist wins** over block for a given name.

Restricted / paused / blocked device modes constrain or replace forwarding **before** per-query allow/block evaluation where implemented in the server path.

## DNS

- **UDP** and **TCP** listeners on `dns.listen_addr` (same port; length-prefixed messages on TCP per RFC 1035 §4.2.2).
- Parses a single uncompressed question in the UDP path; filter; block response or forward.
- **Caching:** `dns.cache` in config — positive answers use min(first RR TTL, `max_ttl_secs`) with floor `min_ttl_secs`; NXDOMAIN uses `negative_ttl_secs`. Disable with `cache.enabled = false`.
- **`dns_paused`:** `POST /pause` toggles in-process pause; **`POST /dns/pause`** / **`POST /dns/resume`** set pause without toggling. When paused, UDP/TCP answer **SERVFAIL** and do not forward.
- **Failure mode:** If **UDP** DNS cannot bind, the UDP task idles, `GET /health` reports **`dns_udp_bound: false`** (and legacy **`dns_bound: false`**), and **`engine_status`** becomes **`error`**. **TCP** bind is tracked separately (`dns_tcp_bound`, `dns_tcp_last_error`); **TCP-only** failure does **not** set **`engine_status`** to **`error`**. UDP can succeed while TCP fails (e.g. partial port conflict). On macOS, **`lsof`** may show **mDNSResponder** on UDP 53-related activity; use **`dns_*_bound`** and bind error strings on **`/health`** plus launchd logs, not `lsof` alone, to decide if the engine is actually blocked.
- **Operational checks:** `packaging/macos/scripts/preflight.sh` summarizes ports, paths, and optional **`curl /health`**.
- **Protection / setup proof (`GET /health` → `protection`):** Distinct clients, query volume in the window, and `last_query_ms` / `recent_client_activity` use **non-loopback** `dns_queries.device_id` rows only (see `storage::queries::NON_LOOPBACK_LAN_DEVICE_SQL`) so local resolver tests do not read as “LAN protected.”

## Threat model (local API)

- HTTP API binds **127.0.0.1** only (see `api.listen_addr`); do not expose to `0.0.0.0` without an explicit product decision.
- **Authentication:** A random token is written to **`paths::token_path()`** (`engine/src/system/paths.rs` — respects **`NETSENTRIX_DATA_DIR`**). Mutating routes require `Authorization: Bearer <token>` (see `engine/src/api/auth.rs`, `docs/api.md`).

## Control plane semantics

- **`POST /pause` / `POST /dns/pause` / `POST /dns/resume`:** See `docs/api.md` — pause is **wired** in the DNS loops.
- **`POST /engine/restart` / `POST /engine/stop`:** Treat as **placeholders** until defined; prefer **launchctl** for real process lifecycle. Stopping the engine while the router still points DHCP DNS at this host breaks LAN DNS — document in Setup UI.

## PacketSniffer

Reference-only under `devprojects/PacketSniffer`; no code import from that project.
