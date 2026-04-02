# launchd — NetSentrix Core (system LaunchDaemon)

Template: [`com.netsentrix.engine.plist`](./com.netsentrix.engine.plist)

## MVP deployment model

| Piece | Role |
|--------|------|
| **This job** | Runs **netsentrix-engine** as **root** (no `UserName`) so **UDP/TCP :53** can bind when `dns.listen_addr` uses port 53. |
| **macOS app** | Runs as the **logged-in user**; talks to `http://127.0.0.1:<api_port>` and reads **`api.token`** from disk. |

## Plist keys (what they do)

- **`ProgramArguments`:** Full path to the engine binary. **Edit** if you install outside `/usr/local/bin/`.
- **`EnvironmentVariables`:** The shipped template sets **`NETSENTRIX_CONFIG`** and **`NETSENTRIX_DATA_DIR`** so config, SQLite, and the API token live under **`/usr/local/etc`** and **`/usr/local/var/netsentrix`** instead of `/var/root/Library/...`. Adjust paths to match your site; create parent directories before first `bootstrap` if needed (`sudo mkdir -p …`).
- **`RunAtLoad`:** Start when the system loads the daemon.
- **`KeepAlive`:** Restart the process if it exits (e.g. crash). Use logs to distinguish crash loops from clean stops.
- **`ThrottleInterval`:** Minimum seconds between restarts — reduces tight respawn if the binary exits immediately (e.g. config error).
- **`StandardOutPath` / `StandardErrorPath`:** Engine stdout/stderr (tracing). Ensure the containing directory exists or is writable; launchd typically creates the files. Rotate with **newsyslog** or your own tooling.
- **`WorkingDirectory`:** Set to `/var/root` for a conventional root daemon; the engine does not depend on cwd for config (paths come from env + `dirs`).

## Token / DB vs the GUI app

Without **`NETSENTRIX_DATA_DIR`**, a root daemon stores the token under **`/var/root/Library/Application Support/NetSentrix/`**, while the app looks under **`~/Library/Application Support/NetSentrix/`** for the GUI user — **different paths**. The template **`NETSENTRIX_DATA_DIR`** layout is the supported way to put **`…/NetSentrix/api.token`** on a path you can permission for both engine and operator (see [`../installer/BUILD.md`](../installer/BUILD.md)).

## Not in scope here

- **SMJobBless** / privileged helper installers
- Signed / notarized **.pkg** automation (see Apple documentation when you ship)

Full Mac mini flow: [`../installer/BUILD.md`](../installer/BUILD.md).
