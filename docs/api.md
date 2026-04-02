# NetSentrix — local API

All endpoints are **JSON** over HTTP unless noted. The server binds to **`127.0.0.1`** only (see `api.listen_addr` in config).

## Response envelope

Most routes return:

```json
{ "ok": true, "data": { } }
```

Errors:

```json
{ "ok": false, "error": { "code": "string", "message": "string" } }
```

**Exception:** `GET /health` returns a **flat** JSON object (no envelope) for quick diagnostics.

## Authentication

On first run the engine creates a random token and writes it to:

- **macOS:** `~/Library/Application Support/NetSentrix/api.token`  
  (same path `dirs::data_dir()` uses on other platforms)

The Swift app reads this file and sends:

```http
Authorization: Bearer <token>
```

**Bearer is required** for every route on the **authenticated** router:

| Method | Path |
|--------|------|
| POST | `/settings` |
| POST | `/reload` |
| POST | `/block` |
| POST | `/allow` |
| POST | `/pause` |
| POST | `/dns/pause` |
| POST | `/dns/resume` |
| POST | `/engine/restart` |
| POST | `/engine/stop` |
| PATCH | `/devices/:id` |

**No Bearer** (read-only / diagnostics):

- `GET /health`, `GET /stats`, `GET /queries`, `GET /settings`, `GET /devices`, `GET /devices/:id`, `GET /alerts`, WebSocket `GET /ws`

Invalid or missing Bearer on protected routes → **401 Unauthorized**.

## Implemented routes

### `GET /health`

Flat JSON: `version`, `engine`, `api_listen`, `dns_listen`, **`dns_udp_bound`**, **`dns_tcp_bound`**, **`dns_bound`** (legacy, same as `dns_udp_bound`), **`dns_last_error`** (UDP bind), **`dns_tcp_last_error`** (TCP bind, if any), `engine_status` (`starting` \| `running` \| `stopped` \| `error` — **`error`** is set on **UDP** DNS bind failure; **TCP-only** bind failure does not flip this; see `engine/src/system/runtime.rs`), `suggested_lan_ip`, **`sniffer_enabled`** (always **`false`** in MVP — packet capture not shipped), `alerts_total`, `api_token_file`, **`config_path`**, **`netsentrix_data_dir`** (directory containing `api.token` / default DB basename), **`db_path`** (active SQLite path from config), `dns_paused`, **`last_client_query_ms`** (epoch ms of latest **`dns_queries`** row whose `device_id` is a **non-loopback** LAN client key — excludes `ip:127.*` and `ip:::1`; null if none), **`recent_client_activity`** (true when that timestamp falls within the last `protection.window_seconds`).

**`protection`** (authoritative for UI): `state` (`not_active` \| `partial` \| `active`), `reasons` (machine-readable codes such as `dns_paused`, `dns_not_bound`, `listen_loopback_only`, `no_recent_lan_queries`, `engine_error`, `db_unavailable`), `window_seconds`, `distinct_clients_in_window`, **`lan_query_count_in_window`** (row count from non-loopback LAN clients in the window), **`last_query_ms`** (same LAN-only semantics as top-level LAN proof; null if none), `lan_capable`, `dns_listen`.

### `GET /stats`

Envelope → `data`: `total_queries`, `blocked_queries`, `allowed_queries`, `blocked_percent`, `distinct_devices`, `alerts_total`, `alerts_last_24h`, `dns_cache_hits`, `dns_cache_misses`.

**Semantics:** `allowed_queries` counts rows with `action` **`allowed`** or **`allowed_cached`**. `blocked_queries` counts **`blocked`** and **`blocked_forwarded`**. Percentages use `total_queries` as the denominator.

### `GET /queries`

Query params: `limit` (default 50, max 500), optional `before_id` (cursor).

Envelope → `data`: array of `{ id, timestamp_ms, device_id, domain, query_type, action, latency_ms }`.

### `GET /settings` / `POST /settings`

GET: envelope → `data`: `{ dns: { listen_addr, upstream, blocklist_paths, allowlist_paths, block_policy }, api_listen }`.

POST (Bearer): body `{ "dns": { "upstream"?: "...", "blocklist_paths"?: [...], "allowlist_paths"?: [...], "block_policy"?: "a_zero" | "nx_domain", "protection_activity_window_secs"?: <u64> } }`. Persists config and reloads the in-memory DNS filter. `protection_activity_window_secs` is clamped between 10 and 86400.

### `GET /devices`, `GET /devices/:id`, `PATCH /devices/:id`

List / get device rows from SQLite (DNS-visibility MVP). Each device includes:

- Core: `id` (e.g. `ip:192.168.1.10`), `ip_address`, `name`, `first_seen`, `last_seen` (epoch ms), `mac_address`, `hostname`, `vendor` (usually `null` until discovery/enrichment exists).
- **`query_count_total`**: count of `dns_queries` rows for this `device_id` (lifetime in DB).
- **`query_count_24h`**: same count restricted to a **rolling 24h** window ending when the request is handled.
- **`recently_seen_dns`**: `true` when `last_seen` falls in that same rolling 24h window.
- **`is_active`**: currently always `1` on upsert (not a staleness flag yet).
- **`is_protected`**: reserved — **always `false`** until per-device policy exists; do not surface as “protected” in product UI.

PATCH (Bearer): `{ "name": "..." }`.

### `GET /alerts`

Envelope → `data`: recent alert rows (`id`, `timestamp_ms`, `device_id`, `severity`, `category`, `message`, `details_json`).

### `POST /block`, `POST /allow`

Bearer. Body `{ "pattern": "domain-or-suffix" }` — dynamic rules + filter reload (see engine implementation).

### `POST /reload`

Bearer. Reload config from disk and refresh filter.

### `POST /pause`

Bearer. **Toggles** `dns_paused`: when `true`, the engine answers **SERVFAIL** on UDP/TCP DNS and does not forward (toggle again to resume). Response: `{ "ok": true, "data": { "dns_paused": <bool> } }`. `GET /health` includes `dns_paused`. Prefer **`POST /dns/pause`** and **`POST /dns/resume`** for non-toggle semantics (retries cannot accidentally flip twice).

### `POST /dns/pause`, `POST /dns/resume`

Bearer. Sets `dns_paused` to `true` or `false` respectively (idempotent). Response shape matches `/pause` data field.

### `POST /engine/restart`, `POST /engine/stop`

Bearer. **No-ops / placeholders** — do not assume the LAN DNS process exits or restarts. Use **launchctl** (or equivalent) for real service lifecycle. Documented so clients do not imply “safe to unplug” while router DHCP still points here.

### WebSocket `GET /ws`

Upgrade to WebSocket; JSON messages with DNS-related event shapes for live tail (see `engine/src/api/websocket.rs`).

## Client default port

The template config uses **`127.0.0.1:8756`** for the API so unprivileged dev does not require port 53. DNS listen may use another port in dev; production may use `:53` with appropriate privileges.
