# macOS scripts

## `preflight.sh`

Operator checklist before or after installing the engine:

- Engine binary at `/usr/local/bin/netsentrix-engine` (configurable expectation; adjust if you install elsewhere).
- **`NETSENTRIX_CONFIG`** / **`NETSENTRIX_DATA_DIR`** interpretation and token/DB layout (see `engine/src/system/paths.rs`).
- **UDP and TCP port 53** visibility via `lsof` (with notes about **mDNSResponder** vs real bind failures — confirm with **`GET /health`**).
- Default **API port 8756** listener check.
- **launchd** registration for `com.netsentrix.engine`.
- Optional **`curl`** probe of **`http://127.0.0.1:8756/health`**.

The script is **read-only** (no process killing, no automatic reconfiguration). Run:

```bash
bash packaging/macos/scripts/preflight.sh
```

From the repo root, or copy the script to the Mac mini and run it there.
