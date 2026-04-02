# NetSentrix — storage schema (SQLite)

**Status:** Schema is applied at engine startup via **`storage::migrations::run_migrations`** (`engine/src/storage/migrations.rs`), using SQLite **`PRAGMA user_version`** for ordering. Baseline DDL remains **`CREATE IF NOT EXISTS`** inside migration 1 so existing DBs created before versioning upgrade cleanly.

## Versioning

| `user_version` | Meaning |
|----------------|--------|
| **0** | Never migrated, or legacy DB from pre-migration builds. |
| **1** | Baseline tables + indexes (current shipping schema). |

`CURRENT_SCHEMA_VERSION` in `migrations.rs` must be bumped when a new migration is added. If a database’s `user_version` is **greater** than the engine expects, startup **fails** with a clear error (avoid running an old binary against a newer schema).

See **Migrations** below for how to add future steps.

## Tables

### `devices`

Populated when DNS queries are logged (`device_id` like `ip:…`); rename via API PATCH. **`GET /devices`** does not store query counts on this row — it aggregates from **`dns_queries`** (total + rolling 24h) at read time.

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

**`action` (engine):** includes `allowed`, `allowed_cached`, `blocked`, `blocked_forwarded`, etc. **`GET /stats`** maps `allowed_queries` / `blocked_queries` to those sets — see `docs/api.md`.

**Indexes:** `idx_dns_queries_ts` (`timestamp`), `idx_dns_queries_domain` (`domain`), `idx_dns_queries_device_id` (`device_id`).

### `alerts`

Populated when rules/alerting are implemented (Phase 3+). Schema is ready for list endpoints.

### `settings`

Key/value table exists for future app-managed prefs **separate from** TOML config. No Rust `storage::settings` module currently; CRUD can be added when needed.

### `rules`

Dynamic `dns_block` / `dns_allow` rows merged into the in-memory filter (`dns/filter.rs`). Full rules engine modules under `engine/src/rules/` are still mostly stubs.

## Migrations

1. Open the DB (`storage/db.rs`).
2. Call **`run_migrations(conn)`** immediately after open (`main.rs`).
3. Runner reads **`PRAGMA user_version`**, then applies **`apply_migration_N`** for each missing `N` up to **`CURRENT_SCHEMA_VERSION`**, setting **`user_version = N`** after each successful step.

**Adding migration 2 (example):**

1. Implement `apply_migration_2(conn)` with additive DDL (`ALTER TABLE`, new indexes, etc.).
2. Extend the `match next` in `run_migrations` with `2 => apply_migration_2(conn)?`.
3. Set **`CURRENT_SCHEMA_VERSION`** to **`2`**.

No rollback support — keep migrations small and forward-only. Do not use Diesel/SeaORM/sqlx migration CLI; this layer is intentionally minimal.
