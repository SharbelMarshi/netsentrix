# NetSentrix — roadmap

## Done (foundation — matches current tree)

- Monorepo: `engine/` (Rust), `app/` (SwiftPM), `docs/`, `packaging/macos/`.
- **Config:** TOML load/save; `NETSENTRIX_CONFIG` or default path via `dirs::config_dir()/NetSentrix/config.toml` (see `docs/architecture.md`).
- **SQLite:** WAL, foreign keys, `dns_queries`, `devices`, `alerts`, `rules`, `settings` table; indexes on query time/domain/device_id (see `docs/storage-schema.md`).
- **DNS (UDP):** Parse first question, allow/block lists + DB rules, sinkhole/NXDOMAIN, forward to upstream, log rows, event bus, device upsert from client IP.
- **API:** Axum on `127.0.0.1`; JSON envelope on most routes; flat `GET /health`; Bearer token on mutating router; WebSocket `/ws` (server).
- **App:** SwiftUI sidebar + Dashboard, Setup, Devices, Queries, Alerts, Settings; REST client + token file; dark-first UI.

## In progress / next (engineering backlog)

1. **DNS hardening:** Response cache + negative cache; TCP :53 parallel listener; CNAME depth limits (as needed).
2. **Control plane:** `POST /pause` wired to DNS loop; document `POST /engine/restart|stop` (launchctl vs in-process).
3. **Health / UX:** Last-client-query age for protection heuristic; Setup/Dashboard copy (engine vs network protection).
4. **App:** Optional WebSocket client for live Queries; Settings parity (list paths, block policy in UI).
5. **Packaging:** launchd plist + preflight + Mac mini install doc.

## Phase 3+ (deferred)

- Sniffer (`--features sniffer`), GeoIP/enrich, behavioral rules + alert generation from rules engine.
- Signed installer / SMJobBless for production port 53.

## Explicitly not planned (near term)

- Cloud sync, remote admin UI, binding API to non-localhost.
- Copying PacketSniffer code wholesale (reference-only).
