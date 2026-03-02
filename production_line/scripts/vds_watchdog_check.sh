#!/usr/bin/env bash
set -euo pipefail

# VDS watchdog check: verifies motherboard freshness + terminal process count.
# Usage: ./production_line/scripts/vds_watchdog_check.sh [warn_stale_sec] [min_terminals]

VDS_MOTHERBOARD_URL="${VDS_MOTHERBOARD_URL:-http://46.250.244.188:8788}"
WARN_STALE_SEC="${1:-90}"
MIN_TERMINALS="${2:-2}"

status_json="$(curl -fsS --max-time 20 "${VDS_MOTHERBOARD_URL}/api/status")"
terminal_json="$(curl -fsS --max-time 20 -X POST "${VDS_MOTHERBOARD_URL}/api/control/status")"

last_sync="$(printf '%s' "$status_json" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('telemetry',{}).get('generatedAt') or '')")"
term_count="$(printf '%s' "$terminal_json" | python3 -c "import sys,json;d=json.load(sys.stdin);rows=d.get('stdout','').strip().splitlines();print(len([r for r in rows if r.strip()]))")"

now_epoch="$(date +%s)"
if [ -n "$last_sync" ]; then
  sync_epoch="$(python3 -c 'import datetime,sys
s=sys.argv[1] if len(sys.argv)>1 else ""
try:
 print(int(datetime.datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()))
except Exception:
 print(0)' "$last_sync")"
else
  sync_epoch=0
fi

stale_sec=999999
if [ "$sync_epoch" -gt 0 ]; then
  stale_sec=$(( now_epoch - sync_epoch ))
fi

ok=true
if [ "$stale_sec" -gt "$WARN_STALE_SEC" ]; then ok=false; fi
if [ "$term_count" -lt "$MIN_TERMINALS" ]; then ok=false; fi

printf '{"ok":%s,"vds_url":"%s","telemetry_last":"%s","stale_sec":%s,"terminal64_count":%s,"warn_stale_sec":%s,"min_terminals":%s}\n' \
  "$ok" "$VDS_MOTHERBOARD_URL" "$last_sync" "$stale_sec" "$term_count" "$WARN_STALE_SEC" "$MIN_TERMINALS"

if [ "$ok" != "true" ]; then
  echo "[watchdog] anomaly detected: stale_sec=$stale_sec terminal64_count=$term_count" >&2
  exit 2
fi
