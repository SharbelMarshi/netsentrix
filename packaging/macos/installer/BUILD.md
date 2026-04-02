# macOS install — NetSentrix Core (Mac mini, always-on)

## Supported MVP model

1. **Engine:** **system LaunchDaemon** as **root** → can bind **UDP/TCP :53** when `dns.listen_addr` uses port 53.
2. **App:** **GUI user** → localhost HTTP + Bearer token file.
3. **State on disk:** Use **`NETSENTRIX_CONFIG`** and **`NETSENTRIX_DATA_DIR`** (see plist template and `engine/src/system/paths.rs`) so config, SQLite, and **`api.token`** are not trapped under `/var/root/...` where the menu bar app cannot read them.

Default data layout when env vars are set:

| Variable | Effect |
|----------|--------|
| `NETSENTRIX_CONFIG` | Path to `config.toml` (created with defaults if missing and parent is writable). |
| `NETSENTRIX_DATA_DIR` | Parent of **`NetSentrix/`** → token at **`$NETSENTRIX_DATA_DIR/NetSentrix/api.token`**, default DB path in fresh config **`…/NetSentrix/engine.db`** unless overridden in TOML. |

**Permissions:** Engine (root) must write DB and token; the GUI user must **read** `api.token` (e.g. directory `0755`, token `0640` `root:staff` if the user is in `staff`). Adjust for your org.

**App token path:** The menu bar app reads **`~/Library/Application Support/NetSentrix/api.token`** by default. If the engine stores the token elsewhere (e.g. under **`NETSENTRIX_TOKEN_FILE`** in the plist), either symlink that file into the app’s path or launch the app with the same **`NETSENTRIX_TOKEN_FILE`** environment variable pointing at the engine’s file (e.g. from Terminal for testing). **`GET /health`** exposes **`api_token_file`** for verification.

## Steps

### 1. Build release

```bash
cd engine && cargo build --release
```

Binary: `engine/target/release/netsentrix-engine` (name from `Cargo.toml`).

### 2. Install binary

```bash
sudo cp target/release/netsentrix-engine /usr/local/bin/netsentrix-engine
sudo chmod 755 /usr/local/bin/netsentrix-engine
```

Adjust if you prefer `/opt/netsentrix/` — then edit the plist `ProgramArguments` to match.

### 3. Config and data directories

Match the plist (template uses):

```bash
sudo mkdir -p /usr/local/etc/NetSentrix /usr/local/var/netsentrix/NetSentrix
sudo chown root:staff /usr/local/var/netsentrix /usr/local/var/netsentrix/NetSentrix
sudo chmod 775 /usr/local/var/netsentrix /usr/local/var/netsentrix/NetSentrix
```

Edit **`NETSENTRIX_CONFIG`** / **`NETSENTRIX_DATA_DIR`** in the plist if you use different roots. In `config.toml`, set **`dns.listen_addr`** to **`0.0.0.0:53`** (or your LAN IP) for network DNS; set **`storage.db_path`** explicitly if you want SQLite outside the default under `NETSENTRIX_DATA_DIR/NetSentrix/`.

### 4. launchd

```bash
sudo cp packaging/macos/launchd/com.netsentrix.engine.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.netsentrix.engine.plist
sudo chmod 644 /Library/LaunchDaemons/com.netsentrix.engine.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netsentrix.engine.plist
```

Edit plist **`ProgramArguments`** and **`EnvironmentVariables`** before copying if your paths differ.

### 5. Preflight

```bash
bash packaging/macos/scripts/preflight.sh
```

### 6. Verify health

```bash
curl -s http://127.0.0.1:8756/health | python3 -m json.tool
```

Check:

- **`dns_udp_bound`** / **`dns_tcp_bound`** — both should be **`true`** when you intend to serve DNS on the configured port.
- **`dns_last_error`** / **`dns_tcp_last_error`** — should be null when the corresponding listener bound.
- **`engine_status`** — **`error`** usually means **UDP** DNS bind failed; **TCP-only** failure does **not** flip `engine_status` (UDP can still work).
- **`config_path`**, **`netsentrix_data_dir`**, **`db_path`** — confirm they match your deployment.

### 7. Port 53 conflicts (macOS)

- **`lsof`** may show **mDNSResponder** on UDP 53-related sockets; that is **not always** the same as your engine failing to bind. Treat **`GET /health`** and engine logs under **`/var/log/netsentrix-engine*.log`** as authoritative.
- A **TCP listener on :53** often blocks the engine’s TCP DNS side — see **`dns_tcp_bound`** and **`dns_tcp_last_error`**.
- Do **not** kill system services automatically; change **`dns.listen_addr`**, free the port, or use a dedicated appliance policy.

### 8. Router

After health looks correct, set **DHCP DNS** on the router to this host’s **LAN IP**.

## Development

Run `cargo run` from `engine/` with `dns.listen_addr = "127.0.0.1:5353"` so unprivileged dev does not need port 53.

## Distribution

Sign + notarize the binary and any installer (Apple Developer Program). **SMJobBless** / privileged helper is out of scope for this document.
