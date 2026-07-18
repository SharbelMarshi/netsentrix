# NetSentrix

Local-first network intelligence for macOS. A Rust engine (NetSentrix Core) handles DNS filtering, query logging, and a localhost-only control API; a SwiftUI app is the product UI.

## Layout

- `engine/` — Rust daemon: DNS server, SQLite storage, HTTP API on 127.0.0.1
- `app/` — SwiftUI macOS client (Swift package; open `Package.swift` in Xcode)
- `docs/` — architecture, API contract, storage schema, roadmap
- `packaging/macos/` — launchd plist, preflight script, Mac mini install notes

## Running the engine

```bash
cd engine && cargo run
```

Config is read from `NETSENTRIX_CONFIG`, falling back to `<config_dir>/NetSentrix/config.toml`. The API token and database live under the data dir: `NETSENTRIX_TOKEN_FILE` wins if set, then `NETSENTRIX_DATA_DIR/NetSentrix/api.token`, then `<data_dir>/NetSentrix/api.token`. Path resolution lives in `engine/src/system/paths.rs`.

The API listens on port 8756 by default. The config template points DNS at a non-53 port for development; set `dns.listen_addr` to `:53` (needs privileges) to serve the LAN.

One gotcha when running as a root LaunchDaemon: without `NETSENTRIX_DATA_DIR`, the engine writes its token and DB under `/var/root/Library/Application Support/NetSentrix/`, while the GUI app reads `~/Library/Application Support/NetSentrix/api.token`. Set `NETSENTRIX_DATA_DIR` in the plist (see `packaging/macos/launchd/`) so both processes agree.

## Running the app

```bash
cd app && swift run NetSentrix
```

Or open `app/Package.swift` in Xcode and run the `NetSentrix` target. `#Preview` macros are left out of the sources because plain `swift build` can't compile them; add previews back in Xcode-only targets if you want them.

A `Makefile` at the repo root has shortcuts (`make engine`, `make app`, `make test-engine`, `make test-app`). CI runs clippy (warnings fail the build), `cargo test`, `swift build`, and `swift test` on every push.

## Building the app bundle

```bash
make bundle        # dist/NetSentrix.app (release build, icon, ad-hoc signed)
make bundle-full   # same, plus the Rust engine embedded in Contents/Resources/bin/
```

The bundler is a Swift script at `packaging/macos/app/bundle.swift`. It renders the app icon from `docs/assets/logo-crystal-mark.svg` with AppKit, so there are no external tool dependencies. The result is ad-hoc signed — fine for local use; distribution to other Macs needs a Developer ID certificate and notarization.

## What works today

The engine serves DNS over UDP and TCP with a response cache, blocklist/allowlist and DB-backed rules, and query logging in SQLite (WAL mode, `user_version` migrations). The API covers health (including engine-derived protection status), settings, block/allow, DNS pause/resume, scheduled per-device policy windows, and a WebSocket at `/ws` fed by the internal event bus.

The app has Dashboard, Setup, Devices, Queries (REST polling plus a live WebSocket feed that reconnects with backoff), Alerts, and Settings screens, and authenticates with the Bearer token from the path above. App preferences — engine address, token file, alert notifications — live in the native Settings window (⌘,); a Go menu gives ⌘1–⌘6 navigation and ⌘R refresh. It also ships a menu bar status item with DNS pause/resume, macOS notifications for new alerts, a scheduled-DNS-policies editor, and follows the system light/dark appearance. Bundles built with `make bundle-full` can install the embedded engine as a LaunchDaemon straight from the sidebar Settings screen (SMAppService; approval in System Settings → Login Items).

Not shipped yet: packet capture (`engine/src/sniffer/` only holds event types for future work), and the enrich and behavioral-rules trees are stubs.

Details live in `docs/roadmap.md`, `docs/architecture.md`, and `docs/api.md`. Working notes (UI debugging, settings parity audit) are in `docs/notes/`.

## License

Proprietary — all rights reserved. See `LICENSE`.
