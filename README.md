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

**Runtime paths** (single MVP model — details in `engine/src/system/paths.rs`):

| Item | Resolution |
|------|------------|
| Config | `NETSENTRIX_CONFIG` or `<config_dir>/NetSentrix/config.toml` |
| Token + default DB layout | `NETSENTRIX_TOKEN_FILE` if set, else `NETSENTRIX_DATA_DIR/NetSentrix/api.token` if `NETSENTRIX_DATA_DIR` set, else `<data_dir>/NetSentrix/api.token` |

**LaunchDaemon as root:** Without **`NETSENTRIX_DATA_DIR`**, token/DB default to **`/var/root/Library/Application Support/NetSentrix/`** while the GUI app reads **`~/Library/Application Support/NetSentrix/api.token`** — use the plist’s **`NETSENTRIX_DATA_DIR`** (see `packaging/macos/launchd/`) so both processes agree.

**App**:

```bash
cd app && swift build && swift run NetSentrix
```

Or open `app/Package.swift` in Xcode and run the `NetSentrix` executable target.

**Note:** `swift build` does not support `#Preview` macros; previews are omitted so CLI builds succeed. Re-add `#Preview` in Xcode-only targets if desired.

**Shortcuts:** `Makefile` at repo root (`make engine`, `make app`, `make test-engine`, `make test-app`). **CI** runs `cargo clippy`, `cargo test`, and `swift build` (see `.github/workflows/ci.yml`).

**Misc:** A stray `package-lock.json` at the repo root is not part of the Rust/Swift workflow; remove or ignore unless you add a Node-based tool.

## Status

**Engine:** localhost Axum API (health + envelope routes), SQLite (WAL + **`user_version` migrations** in `engine/src/storage/migrations.rs`), **UDP and TCP DNS** on `dns.listen_addr`, response **cache**, list + DB rules, query logging, **engine-derived `protection` on `/health`**, `dns_paused` + `/pause` and `/dns/pause`/`/dns/resume`, event bus + **WebSocket `/ws`**. **Packet capture (sniffer)** is **not shipped** — no Cargo feature; `engine/src/sniffer/` holds event DTOs for future work only. **Enrich** and **behavioral rules** trees are **stubs**. **App:** SwiftUI shell with Dashboard, Setup, Devices (rename uses Bearer), Queries (REST + live WS), Alerts, Settings. API token: `~/Library/Application Support/NetSentrix/api.token` (same dir family as `dirs::data_dir()`). **Dev vs prod:** API defaults to port **8756**; DNS often uses a **non-53** port in the template — set `dns.listen_addr` to `:53` for LAN service (requires privileges). See `docs/roadmap.md`, `docs/architecture.md`, `docs/api.md`.

**Packaging:** `packaging/macos/launchd/` plist (`NETSENTRIX_CONFIG` + **`NETSENTRIX_DATA_DIR`** template), `scripts/preflight.sh` (paths, UDP/TCP :53, API port, launchd, optional `curl /health`), `installer/BUILD.md` (Mac mini install sequence).

## Reference-only

`PacketSniffer` elsewhere in `devprojects/` is not part of this repo and must not be copied in wholesale.
