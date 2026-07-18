# Settings parity audit (operator UI vs engine)

Use this checklist against `docs/api.md` and the running engine. **Phase 4:** complete the audit before large UI changes, then implement gaps, then sync docs.

| Capability | Engine surface | App (Settings / elsewhere) |
|------------|----------------|----------------------------|
| Upstream resolver | `POST /settings` (`dns.upstream`) | Settings → Save upstream |
| Block response policy | `POST /settings` (`dns.block_policy`) | Settings → Save block policy |
| Block/allow list paths | `POST /settings` (`blocklist_paths`, `allowlist_paths`) | Settings → Save list paths |
| Protection activity window | `POST /settings` (`protection_activity_window_secs`) | Settings → Save window |
| Quick domain block/allow | `POST /block`, `POST /allow` | Settings + Queries |
| DNS pause / resume | `POST /dns/pause`, `POST /dns/resume` | Settings → DNS answering |
| Reload config | `POST /reload` | Settings → Reload from disk |
| Export CSV | `GET /queries/export.csv` | Settings → Export queries |
| Runtime paths / pause | `GET /health` | Settings → Runtime (from health) |
| Time overrides | `GET/POST/DELETE /policy/time-overrides` | Settings → Scheduled DNS policies |
| Engine API address | (client-side) | Settings → Engine connection |
| Engine daemon install | SMAppService (embedded plist) | Settings → Engine process |
| Alert notifications | `GET /alerts` (polled) | Settings → Notifications |

Update this table when routes or screens change.
