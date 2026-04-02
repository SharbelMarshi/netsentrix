# macOS install — NetSentrix Core (Mac mini)

## Goals

- Engine runs at boot, can bind **UDP/TCP DNS** (port 53 requires **root**).
- Local API stays on **127.0.0.1**; app on the same machine uses Bearer token file.

## Steps

1. **Build release**

   ```bash
   cd engine && cargo build --release
   ```

   Binary: `engine/target/release/netsentrix-engine` (name from `Cargo.toml`).

2. **Install binary**

   ```bash
   sudo cp target/release/netsentrix-engine /usr/local/bin/netsentrix-engine
   sudo chmod 755 /usr/local/bin/netsentrix-engine
   ```

   Adjust path if you prefer `/opt/netsentrix/`.

3. **Config**

   - First run as the target user creates default TOML under `dirs::config_dir()/NetSentrix/config.toml`, or set **`NETSENTRIX_CONFIG`** in the plist.
   - Set `dns.listen_addr` to `0.0.0.0:53` (or your LAN interface) for network-wide DNS.
   - Ensure `storage.db_path` and token path are writable (default under Application Support for the user running the daemon — **if running as root**, paths resolve to `/var/root/...`; consider explicit paths in TOML).

   **Runbook (root LaunchDaemon vs user data):** LaunchDaemons often run as **root** (`WorkingDirectory` may be `/var/root`). Default `dirs::data_dir()` then points under **`/var/root/Library/Application Support/NetSentrix/`** (SQLite DB, API token). The menu-bar app on a logged-in user reads **`~/Library/Application Support/NetSentrix/api.token`**. If the app cannot authenticate, either run the engine as that user, **or** set `storage.db_path` and align token location via deployment docs, **or** copy/sync the token path the app expects. Prefer explicit absolute paths in `config.toml` for production appliances (e.g. Mac mini) so backups and permissions are obvious.

4. **launchd**

   ```bash
   sudo cp packaging/macos/launchd/com.netsentrix.engine.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.netsentrix.engine.plist
   sudo chmod 644 /Library/LaunchDaemons/com.netsentrix.engine.plist
   sudo launchctl bootstrap system /Library/LaunchDaemons/com.netsentrix.engine.plist
   ```

   Edit plist `ProgramArguments` before copying if the binary is not in `/usr/local/bin/`.

5. **Preflight**

   ```bash
   bash packaging/macos/scripts/preflight.sh
   ```

6. **Router**

   After `curl -s http://127.0.0.1:8756/health` succeeds on the Mac, set **DHCP DNS** on the router to this host’s **LAN IP**.

7. **Distribution**

   Sign + notarize binary and any installer package (Apple Developer Program). SMJobBless / privileged helper is out of scope for this outline.

## Development

Run `cargo run` from `engine/` with `dns.listen_addr = "127.0.0.1:5353"` so unprivileged dev does not need port 53.
