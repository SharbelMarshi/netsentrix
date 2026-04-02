# NetSentrix — storage schema (SQLite)

**Status:** Baseline DDL applied on engine startup in `engine/src/storage/schema.rs`. New installs get full schema; existing DBs keep `CREATE IF NOT EXISTS` behavior. **No formal migration runner** yet beyond idempotent DDL.

## Tables

### `devices`

Populated when DNS queries are logged (`device_id` like `ip:…`); rename via API PATCH.

- `id` TEXT PRIMARY KEY  
- `ip_address` TEXT NOT NULL  
- `mac_address`, `hostname`, `vendor`, `name` TEXT  
- `first_seen`, `last_seen` INTEGER  
- `is_active`, `is_protected` INTEGER  

### `dns_queries`

- `id` INTEGER PRIMARY KEY AUTOINCREMENT  
- `timestamp` INTEGER NOT NULL (epoch ms)  
- `device_id` TEXT  
- `domain` TEXT NOT NULL  
- `query_type`, `action`, `upstream_response`, `latency_ms`  

**Indexes:** `idx_dns_queries_ts` (`timestamp`), `idx_dns_queries_domain` (`domain`), `idx_dns_queries_device_id` (`device_id`).

### `alerts`

Populated when rules/alerting are implemented (Phase 3+). Schema is ready for list endpoints.

### `settings`

Key/value table exists for future app-managed prefs **separate from** TOML config. No Rust `storage::settings` module currently; CRUD can be added when needed.

### `rules`

Dynamic `dns_block` / `dns_allow` rows merged into the in-memory filter (`dns/filter.rs`). Full rules engine modules under `engine/src/rules/` are still mostly stubs.

## Migrations

- Today: `init()` runs `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`.  
- **Future:** `PRAGMA user_version` or a small migration table for additive changes.
