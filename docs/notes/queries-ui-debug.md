# Queries / Alerts UI — debugging notes

## Live vs polled queries

- **WebSocket (`GET /ws`):** pushes recent DNS events into the app for a near-live list.
- **REST (`GET /queries`):** polled on a fixed interval to stay aligned with SQLite and to recover if the socket drops.

See `docs/api.md` for `/queries` and `/ws`.

## Repro checklist (focus / selection / AppKit)

1. Run the engine and open the NetSentrix app.
2. Go to **Queries**, confirm the engine is reachable.
3. Leave **Queries** open; generate LAN DNS traffic so rows update frequently.
4. Select a row; use **Block domain** / **Allow** and context menus.
5. From **Alerts**, use **View queries** / **View device activity** and confirm filter + highlight behave as expected.
6. Watch Console for `NSTableView` / AppKit warnings.

**Rule:** treat warnings as actionable only when they correlate with a **reproducible** user-visible bug (wrong selection, stuck focus, missing row). Do not add speculative “fixes” for every console line.
