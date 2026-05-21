# NetSentrix on Mac mini (headless appliance)

Use this as a **Phase 10** operator checklist; it does not replace your security review.

1. **Static LAN IP** — Assign a fixed IPv4 on Ethernet (or reliable Wi‑Fi) so router DHCP DNS can point to a stable address.
2. **Engine binary + launchd** — Install `netsentrix-engine`, use `packaging/macos/launchd/com.netsentrix.engine.plist` (adjust paths). Run `scripts/preflight.sh` after changes.
3. **Privileged DNS** — Binding UDP/TCP `:53` requires root for the daemon; verify `GET /health` shows `dns_udp_bound` / `dns_tcp_bound` as expected.
4. **Token + data dir** — The GUI app (on an admin Mac) or scripts must read the same `api.token` as the engine (`NETSENTRIX_DATA_DIR` / default Application Support layout).
5. **Router** — Set DHCP DNS primary to the Mac mini LAN IP; renew leases; confirm non-loopback rows in **Queries** and `protection` on `/health`.
6. **Backups** — Snapshot `config.toml`, the SQLite file, and custom block/allow lists if you edit them outside the app.

For CSV exports of recent queries, use **Settings → Export query log** or `GET /queries/export.csv` (Bearer).
