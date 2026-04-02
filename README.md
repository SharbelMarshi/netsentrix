# NetSentrix

Local-first network intelligence: **NetSentrix Core** (Rust engine) provides DNS filtering and a localhost control API; the **NetSentrix** macOS app is the product UI.

## Layout

| Path | Role |
|------|------|
| `engine/` | Daemon: DNS, storage, local API (`127.0.0.1` only). |
| `app/` | SwiftUI macOS client (Swift Package; open in Xcode via `Package.swift`). |
| `docs/` | Architecture, API contract, storage schema, roadmap. |
| `packaging/macos/` | launchd / installer / scripts (scaffold). |

## Development

**Engine** (from repo root):

```bash
cd engine && cargo run
```

Default **config** path: `NETSENTRIX_CONFIG` or `<config_dir>/NetSentrix/config.toml` (macOS: typically `~/Library/Application Support/NetSentrix/config.toml` — see `docs/architecture.md`). Default **database** and **API token** also live under platform data dirs (`NetSentrix/`).

**App**:

```bash
cd app && swift build && swift run NetSentrix
```

Or open `app/Package.swift` in Xcode and run the `NetSentrix` executable target.

**Note:** `swift build` does not support `#Preview` macros; previews are omitted so CLI builds succeed. Re-add `#Preview` in Xcode-only targets if desired.

## Status

**Engine:** localhost Axum API (health + envelope routes), SQLite (WAL), UDP DNS forward/block with lists + DB rules, optional response cache / TCP DNS (see engine source), optional `sniffer` feature stub, rules/enrich scaffolded, event bus + WebSocket server on `/ws`. **App:** SwiftUI shell with Dashboard, Setup, Devices (rename uses Bearer), Queries, Alerts, Settings. API token: `~/Library/Application Support/NetSentrix/api.token` (same dir family as `dirs::data_dir()`). **Dev vs prod:** API defaults to port **8756**; DNS often uses a **non-53** port in the template — set `dns.listen_addr` to `:53` for LAN service (requires privileges). See `docs/roadmap.md`, `docs/architecture.md`, `docs/api.md`.

**Packaging:** `packaging/macos/launchd/` plist (paths + optional `NETSENTRIX_CONFIG`), `scripts/preflight.sh` (UDP/TCP :53 checks), `installer/BUILD.md` (Mac mini install sequence).

## Reference-only

`PacketSniffer` elsewhere in `devprojects/` is not part of this repo and must not be copied in wholesale.
