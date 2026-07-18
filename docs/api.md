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
| GET | `/policy/time-overrides` |
| POST | `/policy/time-overrides` |
| DELETE | `/policy/time-overrides/:id` |
| POST | `/feedback/domain` |
| GET | `/queries/export.csv` |

**No Bearer** (read-only / diagnostics):

- `GET /health`, `GET /stats`, `GET /queries`, `GET /settings`, `GET /devices`, `GET /devices/:id`, `GET /alerts`, **`GET /insights/daily`**, WebSocket `GET /ws`

Invalid or missing Bearer on protected routes → **401 Unauthorized**.

## Implemented routes

### `GET /health`

Flat JSON: `version`, `engine`, `api_listen`, `dns_listen`, **`dns_udp_bound`**, **`dns_tcp_bound`**, **`dns_bound`** (legacy, same as `dns_udp_bound`), **`dns_last_error`** (UDP bind), **`dns_tcp_last_error`** (TCP bind, if any), `engine_status` (`starting` \| `running` \| `stopped` \| `error` — **`error`** is set on **UDP** DNS bind failure; **TCP-only** bind failure does not flip this; see `engine/src/system/runtime.rs`), `suggested_lan_ip`, **`sniffer_enabled`** — **`false`** while no live capture loop is running. The optional **`sniffer_capture`** Cargo feature reserves the build-time integration path for Phase 6+ work; default **release** builds omit it. See `docs/sniffer-permissions.md` and `docs/roadmap.md`. `alerts_total`, `api_token_file`, **`config_path`**, **`netsentrix_data_dir`** (directory containing `api.token` / default DB basename), **`db_path`** (active SQLite path from config), `dns_paused`, **`last_client_query_ms`** (epoch ms of latest **`dns_queries`** row whose `device_id` is a **non-loopback** LAN client key — excludes `ip:127.*` and `ip:::1`; null if none), **`recent_client_activity`** (true when that timestamp falls within the last `protection.window_seconds`).

**`protection`** (authoritative for UI): `state` (`not_active` \| `partial` \| `active`), `reasons` (machine-readable codes such as `dns_paused`, `dns_not_bound`, `listen_loopback_only`, `no_recent_lan_queries`, `engine_error`, `db_unavailable`), `window_seconds`, `distinct_clients_in_window`, **`lan_query_count_in_window`** (row count from non-loopback LAN clients in the window), **`last_query_ms`** (same LAN-only semantics as top-level LAN proof; null if none), `lan_capable`, `dns_listen`.

**`setup_hints`** (additive): array of `{ code, severity, title, detail, suggested_fix? }` for human-readable setup guidance derived from the same signals as `protection` plus **honest** heuristics (e.g. IPv6 presence on this host, DNS-visible DoH-style hostnames in recent queries). Treat as hints, not proof of bypass. Documented `code` values include: `dns_paused`, `dns_not_bound`, `listen_loopback_only`, `no_lan_clients_in_window`, `router_dns_may_not_point_here`, `ipv6_dns_bypass_possible`, `possible_doh_hostname_in_queries`, `engine_starting`, `engine_stopped`, `engine_error`, `db_unavailable`.

**Example shape** (non-authoritative; fields vary by engine version): see [`docs/fixtures/health_minimal.json`](fixtures/health_minimal.json).

### `GET /stats`

Envelope → `data`: `total_queries`, `blocked_queries`, `allowed_queries`, `blocked_percent`, `distinct_devices`, `alerts_total`, `alerts_last_24h`, `dns_cache_hits`, `dns_cache_misses`.

**Semantics:** `allowed_queries` counts rows with `action` **`allowed`** or **`allowed_cached`**. `blocked_queries` counts **`blocked`** and **`blocked_forwarded`**. Percentages use `total_queries` as the denominator.

### `GET /insights/daily`

Query params: optional `hours` (default **24**, max **168**).

Envelope → `data`: `window_hours`, `since_ms`, `until_ms`, `top_devices` (`{ device_id, query_count }`[], capped), `top_domains` (`{ domain, query_count, explanation }`[] — `explanation` is a deterministic local classifier string), `peak_hour_local` (0–23 or null), `peak_hour_query_count`.

### `GET /queries`

Query params: `limit` (default 50, max 500), optional `before_id` (cursor), optional **`device_id`** (e.g. `ip:192.168.1.10`) to return rows for that client only.

Envelope → `data`: array of `{ id, timestamp_ms, device_id, domain, query_type, action, latency_ms }`.

### `GET /settings` / `POST /settings`

GET: envelope → `data`: `{ dns: { listen_addr, upstream, blocklist_paths, allowlist_paths, block_policy, protection_activity_window_secs, … }, api_listen }` (full `dns` section mirrors TOML; extra keys are safe to ignore for older clients).

POST (Bearer): body `{ "dns": { "upstream"?: "...", "blocklist_paths"?: [...], "allowlist_paths"?: [...], "block_policy"?: "a_zero" | "nx_domain", "protection_activity_window_secs"?: <u64> } }`. Persists config and reloads the in-memory DNS filter. `protection_activity_window_secs` is clamped between 10 and 86400.

### `GET /devices`, `GET /devices/:id`, `PATCH /devices/:id`

List / get device rows from SQLite (DNS-visibility MVP). Each device includes:

- Core: `id` (e.g. `ip:192.168.1.10`), `ip_address`, `name`, `first_seen`, `last_seen` (epoch ms), `mac_address`, `hostname`, `vendor` (usually `null` until discovery/enrichment exists).
- **`query_count_total`**: count of `dns_queries` rows for this `device_id` (lifetime in DB).
- **`query_count_24h`**: same count restricted to a **rolling 24h** window ending when the request is handled.
- **`recently_seen_dns`**: `true` when `last_seen` falls in that same rolling 24h window.
- **`is_active`**: currently always `1` on upsert (not a staleness flag yet).
- **`is_protected`**: reserved — **always `false`** in current builds; do not surface as “protected” in product UI.
- **`dns_policy`**: stored SQLite value — `normal` \| `restricted` (allowlist-only for that device) \| `paused` (SERVFAIL) \| `blocked` (sinkhole / deny path per engine). `PATCH` updates this field.
- **`effective_dns_policy`**: mode the resolver uses **at request time** — same vocabulary as `dns_policy`, computed with `resolve_effective_dns_policy` (applies matching **`dns_time_overrides`** in **local wall time** on top of the stored row).
- **`schedule_override_active`**: `true` when a enabled time-override row matches this device’s scope and local clock (so effective policy may differ from `dns_policy` even though the stored row is unchanged).
- **`tags`**: comma-separated operator labels (e.g. `Child,Guest`).

Older engines may omit `effective_dns_policy` / `schedule_override_active`; clients should treat missing `effective_dns_policy` as equal to `dns_policy` and missing `schedule_override_active` as `false`.

PATCH (Bearer): `{ "name"?: "...", "dns_policy"?: "normal" | "restricted" | "paused" | "blocked", "tags"?: "comma,separated" }` — partial updates supported (omit fields you do not change).

### `GET /policy/time-overrides` / `POST /policy/time-overrides` / `DELETE /policy/time-overrides/:id`

Bearer. List / create / delete rows in **`dns_time_overrides`**.

- **GET** → envelope array of `{ id, scope_device_id, start_min, end_min, dns_policy, enabled }`.
- **POST** body: `{ "scope_device_id"?: "ip:…" | null, "start_min": 0–1439, "end_min": 0–1439, "dns_policy": "normal" | … }`. `scope_device_id` **omitted** or **null** = all devices. Overnight windows: `start_min > end_min`.
- **DELETE** `:id` — removes one row.

### `POST /feedback/domain`

Bearer. Body `{ "pattern": "domain.example", "verdict": "safe" | "suspicious" }` — upserts **`domain_feedback`**; the alert classifier merges these hints deterministically (no ML).

### `GET /queries/export.csv`

Bearer. Query `hours` (default 24, max 168), `limit` (default 10000, max 50000). Returns **`text/csv`** with columns `id,timestamp_ms,device_id,domain,query_type,action,latency_ms` for recent rows.

### `GET /alerts`

Envelope → `data`: recent alert rows (`id`, `timestamp_ms`, `device_id`, `severity`, `category`, `message`, `details_json`, **`priority`**: `low` \| `medium` \| `high` — rule-based tier derived from `severity`). **`details_json`** is engine-defined JSON; Phase 2.6+ payloads may include compact hints such as `top_domains`, `top_unknown_domains`, `trigger_domain`, `candidate_block_domain`, and `related_device_id` where applicable. Phase 7+ may add **`intel_signals`**: string array of rule-based, human-readable trace lines. **`category`** uses a stable lowercase set (e.g. `repeat_block`, `unknown_spike`) — map in the app for actions.

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

Message shape: `{ "type": "DNS_QUERY" | "DNS_ALLOWED" | "DNS_BLOCKED", "timestamp": ms, "device_id": "ip:…", "payload": { "domain", "action", "client_ip", "query_type" } }`. `query_type` is absent on older engines — clients must treat it as optional.

## Client default port

The template config uses **`127.0.0.1:8756`** for the API so unprivileged dev does not require port 53. DNS listen may use another port in dev; production may use `:53` with appropriate privileges.
