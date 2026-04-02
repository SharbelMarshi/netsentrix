#!/usr/bin/env bash
# NetSentrix Core — operator preflight (macOS). Read-only checks; does not fix or kill processes.
set -euo pipefail

ENGINE_BIN_DEFAULT="/usr/local/bin/netsentrix-engine"
API_PORT_DEFAULT="8756"

echo "=== NetSentrix Core — preflight ==="
echo ""

have_lsof() { command -v lsof >/dev/null 2>&1; }
have_curl() { command -v curl >/dev/null 2>&1; }

# --- 1) Engine binary ---
echo "1) Engine binary"
if [[ -x "$ENGINE_BIN_DEFAULT" ]]; then
  echo "   OK: $ENGINE_BIN_DEFAULT is present and executable."
else
  echo "   WARN: $ENGINE_BIN_DEFAULT missing or not executable."
  echo "   Next: sudo cp engine/target/release/netsentrix-engine $ENGINE_BIN_DEFAULT && sudo chmod 755 $ENGINE_BIN_DEFAULT"
fi
echo ""

# --- 2) Environment / path model ---
echo "2) Runtime path hints (see engine/src/system/paths.rs)"
if [[ -n "${NETSENTRIX_CONFIG:-}" ]]; then
  echo "   NETSENTRIX_CONFIG=$NETSENTRIX_CONFIG"
  if [[ -f "$NETSENTRIX_CONFIG" ]]; then
    echo "   OK: config file exists."
  else
    echo "   WARN: config file does not exist yet (engine may create defaults if parent is writable)."
  fi
else
  echo "   NETSENTRIX_CONFIG (unset) — engine uses default: ~/Library/Application Support/NetSentrix/config.toml"
  echo "   For root LaunchDaemon, default config is under /var/root/Library/... — set NETSENTRIX_CONFIG for a fixed path."
fi
if [[ -n "${NETSENTRIX_TOKEN_FILE:-}" ]]; then
  echo "   NETSENTRIX_TOKEN_FILE=$NETSENTRIX_TOKEN_FILE (overrides default token path)"
fi
if [[ -n "${NETSENTRIX_DATA_DIR:-}" ]]; then
  echo "   NETSENTRIX_DATA_DIR=$NETSENTRIX_DATA_DIR"
  APPDIR="${NETSENTRIX_DATA_DIR}/NetSentrix"
  echo "   Token expected at: ${NETSENTRIX_TOKEN_FILE:-$APPDIR/api.token}"
  echo "   Default DB basename: $APPDIR/engine.db (unless overridden in config.toml)"
  if [[ -d "$NETSENTRIX_DATA_DIR" ]]; then
    echo "   OK: data root directory exists."
  else
    echo "   WARN: data root missing — create before first run: sudo mkdir -p \"$APPDIR\" && sudo chown root:staff \"$NETSENTRIX_DATA_DIR\" \"$APPDIR\""
  fi
else
  echo "   NETSENTRIX_DATA_DIR (unset) — token/db use dirs::data_dir()/NetSentrix/"
  echo "   Root daemon → /var/root/Library/Application Support/NetSentrix/ (GUI user path differs — see BUILD.md)."
fi
echo ""

# --- 3) Writable DB parent (if config exists and mentions db_path we cannot parse TOML here; skip deep check) ---
echo "3) Database parent (heuristic)"
if [[ -n "${NETSENTRIX_CONFIG:-}" && -f "$NETSENTRIX_CONFIG" ]]; then
  echo "   Inspect storage.db_path in $NETSENTRIX_CONFIG — parent directory must be writable by the engine user."
else
  echo "   Set NETSENTRIX_CONFIG or rely on defaults; ensure SQLite parent dir is writable for the engine process."
fi
echo ""

# --- 4) UDP / TCP port 53 ---
echo "4) UDP :53 (LAN DNS — conflicts common on macOS)"
if have_lsof; then
  if lsof -nP -iUDP:53 2>/dev/null | head -8; then
    echo "   Note: mDNSResponder often holds UDP 53 on multicast-related sockets; that is not always the same as"
    echo "   your engine failing to bind a recursive resolver on a specific interface. Compare with engine logs and GET /health."
  else
    echo "   (no UDP :53 sockets reported by lsof, or none visible to this user)"
  fi
else
  echo "   SKIP: lsof not found."
fi
echo ""

echo "5) TCP :53 (DNS over TCP)"
if have_lsof; then
  if lsof -nP -iTCP:53 -sTCP:LISTEN 2>/dev/null | head -8; then
    echo "   WARN: Something is listening on TCP 53 — engine TCP DNS may fail (see health dns_tcp_bound, dns_tcp_last_error)."
  else
    echo "   OK: no TCP listener on :53 reported."
  fi
else
  echo "   SKIP: lsof not found."
fi
echo ""

# --- 5) API port ---
echo "6) API port (default $API_PORT_DEFAULT)"
if have_lsof; then
  if lsof -nP -iTCP:"$API_PORT_DEFAULT" -sTCP:LISTEN 2>/dev/null | head -5; then
    echo "   Something is listening on TCP $API_PORT_DEFAULT (expected if engine is running)."
  else
    echo "   No listener on $API_PORT_DEFAULT (engine may be stopped or using another api.listen_addr)."
  fi
else
  echo "   SKIP: lsof not found."
fi
echo ""

# --- 6) launchd ---
echo "7) launchd (system daemon)"
if [[ -f /Library/LaunchDaemons/com.netsentrix.engine.plist ]]; then
  echo "   Found /Library/LaunchDaemons/com.netsentrix.engine.plist"
  if launchctl print "system/com.netsentrix.engine" >/dev/null 2>&1; then
    echo "   Service is registered in system domain."
  else
    echo "   WARN: plist present but service not registered — sudo launchctl bootstrap system /Library/LaunchDaemons/com.netsentrix.engine.plist"
  fi
else
  echo "   No installed plist at /Library/LaunchDaemons/com.netsentrix.engine.plist (template: packaging/macos/launchd/)."
fi
echo ""

# --- 7) Health ---
echo "8) Health check (optional)"
if have_curl; then
  echo "   curl -sS http://127.0.0.1:${API_PORT_DEFAULT}/health | python3 -m json.tool"
  echo "   Expect: ok, dns_udp_bound / dns_tcp_bound match your dns.listen_addr; dns_last_error null if UDP bound."
  if curl -sfS --max-time 2 "http://127.0.0.1:${API_PORT_DEFAULT}/health" >/dev/null 2>&1; then
    echo "   OK: /health responded."
  else
    echo "   INFO: /health not reachable on 127.0.0.1:${API_PORT_DEFAULT} (engine stopped or different api.listen_addr)."
  fi
else
  echo "   Install curl to probe /health from this script."
fi
echo ""

echo "=== Checklist (summary) ==="
echo " - Port 53: engine needs root for privileged bind; verify UDP+TCP with GET /health, not only lsof."
echo " - Token: GUI app must read the same api.token the engine wrote (NETSENTRIX_DATA_DIR or shared permissions)."
echo " - Logs: /var/log/netsentrix-engine.log and .err (see plist StandardOutPath / StandardErrorPath)."
echo " - Router: point DHCP DNS here only after dns_udp_bound and dns_tcp_bound are acceptable for your policy."
echo ""
