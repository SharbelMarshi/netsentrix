# launchd

Template: `com.netsentrix.engine.plist`

- **ProgramArguments:** Point at the installed `netsentrix-engine` binary (default in plist: `/usr/local/bin/netsentrix-engine`).
- **RunAtLoad / KeepAlive:** Engine restarts if it exits; tune `ThrottleInterval` to avoid tight crash loops.
- **Logs:** `StandardOutPath` / `StandardErrorPath` under `/var/log/` (create or rotate as needed).
- **Port 53:** Binding LAN DNS usually requires this job to run as **root** (system `LaunchDaemon`).
- **Optional:** Uncomment `EnvironmentVariables` → `NETSENTRIX_CONFIG` for a fixed config path.

See `../installer/BUILD.md` for full Mac mini flow.
