# Installer

Two supported paths:

1. **App-managed (preferred):** `make bundle-full` builds `dist/NetSentrix.app` with the
   engine embedded and an SMAppService daemon plist. In the app, Settings → Engine process
   → Install engine registers the LaunchDaemon (approval in System Settings → Login Items).
2. **Manual LaunchDaemon:** copy the engine binary and load the plist by hand — see
   `BUILD.md` and `../launchd/`.

Not started: signed `.pkg`, Developer ID signing, notarization.
