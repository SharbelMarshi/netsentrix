#!/usr/bin/env bash
# Preflight before running or installing NetSentrix Core on macOS.
set -euo pipefail

echo "=== NetSentrix Core — preflight ==="
echo ""

echo "1) UDP :53 (LAN DNS — often needs root / LaunchDaemon)"
if lsof -nP -iUDP:53 2>/dev/null | head -5; then
  echo "   (showing first lines; mDNSResponder may appear — differs from a full recursive resolver on LAN)"
else
  echo "   (none reported or lsof unavailable)"
fi
echo ""

echo "2) TCP :53 (DNS over TCP fallback)"
if lsof -nP -iTCP:53 -sTCP:LISTEN 2>/dev/null | head -5; then
  echo "   Listeners above may conflict with binding the engine to :53."
else
  echo "   No TCP listener on :53 reported."
fi
echo ""

echo "3) Checklist"
echo "   - Dev: use dns.listen_addr such as 127.0.0.1:5353 in config (no root)."
echo "   - Prod Mac mini: set dns.listen_addr to 0.0.0.0:53 (or LAN IP:53), run engine as root via launchd."
echo "   - Update com.netsentrix.engine.plist ProgramArguments to the real binary path."
echo "   - Router DHCP DNS should point to this host only after the engine is stable."
echo "   - After start: curl http://127.0.0.1:<api_port>/health — check dns_udp_bound and dns_tcp_bound (both should be true on :53)."
echo "   - mDNSResponder on :53 is normal on macOS; your engine still needs its own bind strategy (dedicated Mac / port choice)."
echo ""
