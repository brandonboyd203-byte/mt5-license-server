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

echo "[$(date)] autonomous_tick start"

# Quick health probe (non-fatal)
"$ROOT/scripts/vps_health.sh" >/dev/null 2>&1 || true

# Pull latest logs + summarize
"$ROOT/scripts/fetch_latest_vps_report.sh"

# Auto-patch and deploy if rules apply
"$ROOT/scripts/auto_patch_and_deploy.sh" || true

echo "[$(date)] autonomous_tick end"
