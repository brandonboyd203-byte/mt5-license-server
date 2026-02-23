#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/run_logs"
mkdir -p "$LOG_DIR"

LOCK_DIR="$LOG_DIR/.auto_lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Auto tick already running."
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

# shellcheck source=production_line/scripts/vps_env.sh
source "$ROOT/scripts/vps_env.sh"

echo "[$(date)] autonomous_tick start"

# Quick health probe (non-fatal)
"$ROOT/scripts/vps_health.sh" >/dev/null 2>&1 || true

# Pull latest logs + summarize
"$ROOT/scripts/fetch_latest_vps_report.sh" || true

# Ensure all MT5 terminals are running
count=$(vps_ssh "powershell -NoProfile -Command \"(Get-Process terminal64 -ErrorAction SilentlyContinue | Measure-Object).Count\"" 2>/dev/null | tr -d '\r' | tail -n 1 || true)
if [[ -z "$count" || "$count" -lt 6 ]]; then
  echo "[auto] terminal64 count=$count, restarting MT5"
  "$ROOT/scripts/vps_control_live.sh" restart
fi

# Auto-patch and deploy if rules apply
"$ROOT/scripts/auto_patch_and_deploy.sh" || true

echo "[$(date)] autonomous_tick end"
