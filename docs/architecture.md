# NetSentrix — architecture

## Separation

- **Engine (NetSentrix Core):** DNS, persistence, localhost JSON API + WebSocket, optional sniffer (feature flag).
- **App:** SwiftUI product UI; talks to the engine over HTTP/WebSocket on loopback only.

## Processes

- One long-running **engine** process on the always-on Mac (production: `launchd`; see `packaging/macos/launchd/`).
- **App** uses `http://127.0.0.1:<api_port>` (default **8756** in the generated template). The engine exposes WebSocket `GET /ws`; the macOS app may use REST polling until a WS client is wired.

## Configuration

- **Config file:** If `NETSENTRIX_CONFIG` is set, that path is used. Otherwise: **`dirs::config_dir()/NetSentrix/config.toml`** (on macOS this is under *Application Support*; see `engine/src/system/paths.rs` and `config/loader.rs`).
- **Format:** TOML (`engine/src/config/schema.rs`): `api.listen_addr`, `dns.*`, `storage.db_path`.
- **Defaults:** Dev-friendly DNS bind is often **not** `:53` (e.g. `127.0.0.1:5353`); production on a LAN DNS role uses **`0.0.0.0:53`** or similar with appropriate privileges.

## Data

- **SQLite** at `storage.db_path` (default under `dirs::data_dir()/NetSentrix/engine.db`). Tables: devices, dns_queries, alerts, rules, settings — see `docs/storage-schema.md`.
- **WAL** is enabled at open via `PRAGMA journal_mode = WAL` in `storage/schema.rs`. Formal versioned migrations are still minimal (`CREATE IF NOT EXISTS` + indexes).

## DNS

- **UDP** and **TCP** listeners on `dns.listen_addr` (same port; length-prefixed messages on TCP per RFC 1035 §4.2.2).
- Parses a single uncompressed question in the UDP path; filter; block response or forward.
- **Caching:** `dns.cache` in config — positive answers use min(first RR TTL, `max_ttl_secs`) with floor `min_ttl_secs`; NXDOMAIN uses `negative_ttl_secs`. Disable with `cache.enabled = false`.
- **`dns_paused`:** `POST /pause` toggles in-process pause (SERVFAIL, no forward).
- **Failure mode:** If the DNS socket cannot bind, the loop idles and `GET /health` reports `dns_bound: false`. Router DHCP should fall back to ISP/router DNS when this host is not serving DNS (recommended); strict fail-closed is a future config option.

## Threat model (local API)

- HTTP API binds **127.0.0.1** only (see `api.listen_addr`); do not expose to `0.0.0.0` without an explicit product decision.
- **Authentication:** A random token is written to **`dirs::data_dir()/NetSentrix/api.token`**. Mutating routes require `Authorization: Bearer <token>` (see `engine/src/api/auth.rs`, `docs/api.md`).

## Control plane semantics

- **`POST /pause`:** Intended to pause DNS processing in-process (drop or REFUSE) when wired; see `docs/api.md` for current behavior.
- **`POST /engine/restart` / `POST /engine/stop`:** Treat as **placeholders** until defined; prefer **launchctl** for real process lifecycle. Stopping the engine while the router still points DHCP DNS at this host breaks LAN DNS — document in Setup UI.

## PacketSniffer

Reference-only under `devprojects/PacketSniffer`; no code import from that project.
