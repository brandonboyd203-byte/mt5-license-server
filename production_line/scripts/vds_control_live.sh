#!/usr/bin/env bash
set -euo pipefail

# Direct MT5 control via VDS motherboard HTTP control endpoints.
# Usage:
#   ./production_line/scripts/vds_control_live.sh status|pause|resume|restart|telemetry-refresh|health|watchdog-check|watchdog-recover
# Optional env:
#   VDS_MOTHERBOARD_URL (default: http://46.250.244.188:8788)

ACTION="${1:-status}"
VDS_MOTHERBOARD_URL="${VDS_MOTHERBOARD_URL:-http://46.250.244.188:8788}"
TIMEOUT="${VDS_CONTROL_TIMEOUT:-20}"

post_control() {
  local action="$1"
  curl -fsS --max-time "$TIMEOUT" -X POST "${VDS_MOTHERBOARD_URL}/api/control/${action}"
}

get_status() {
  curl -fsS --max-time "$TIMEOUT" "${VDS_MOTHERBOARD_URL}/api/status"
}

case "$ACTION" in
  status)
    echo "=== VDS motherboard status ==="
    get_status
    echo
    echo "=== terminal64 process status ==="
    post_control status
    ;;
  health)
    curl -fsS --max-time "$TIMEOUT" "${VDS_MOTHERBOARD_URL}/api/fast-status"
    ;;
  pause)
    post_control pause
    ;;
  resume)
    post_control resume
    ;;
  restart)
    post_control restart
    ;;
  telemetry-refresh)
    post_control telemetry-refresh
    ;;
  watchdog-check)
    "$(cd "$(dirname "$0")" && pwd)/vds_watchdog_check.sh"
    ;;
  watchdog-recover)
    "$(cd "$(dirname "$0")" && pwd)/vds_watchdog_check.sh" || {
      echo "[watchdog] auto-recovery: triggering telemetry refresh + restart"
      post_control telemetry-refresh >/dev/null || true
      sleep 1
      post_control restart
    }
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 status|pause|resume|restart|telemetry-refresh|health|watchdog-check|watchdog-recover"
    exit 1
    ;;
esac
