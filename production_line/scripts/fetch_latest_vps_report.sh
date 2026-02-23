#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=production_line/scripts/vps_env.sh
source "$ROOT/scripts/vps_env.sh"

STATE_FILE="$ROOT/run_logs/last_report.txt"
LATEST_NAME=$(vps_ssh "powershell -NoProfile -Command \"\$d=Get-ChildItem '$VPS_PATH/reports/raw' -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if (-not \$d) { exit 2 }; \$d.Name\"" || true)

if [[ -z "$LATEST_NAME" ]]; then
  echo "No report folder found on VPS"
  exit 2
fi

LAST_NAME=""
if [[ -f "$STATE_FILE" ]]; then
  LAST_NAME=$(cat "$STATE_FILE" || true)
fi

if [[ "$LATEST_NAME" == "$LAST_NAME" ]]; then
  echo "No new report ($LATEST_NAME)"
  exit 0
fi

echo "New report detected: $LATEST_NAME"

vps_ssh "powershell -NoProfile -Command \"Compress-Archive -Path '$VPS_PATH/reports/raw/$LATEST_NAME\\*' -DestinationPath '$VPS_PATH/reports/latest.zip' -Force\""

mkdir -p "$ROOT/run_logs/latest"
mkdir -p "$ROOT/run_logs/history/$LATEST_NAME"

vps_scp "$VPS_USER@$VPS_HOST:$VPS_PATH/reports/latest.zip" "$ROOT/run_logs/latest/latest.zip"

unzip -o "$ROOT/run_logs/latest/latest.zip" -d "$ROOT/run_logs/latest" >/dev/null || true
unzip -o "$ROOT/run_logs/latest/latest.zip" -d "$ROOT/run_logs/history/$LATEST_NAME" >/dev/null || true
python3 "$ROOT/scripts/normalize_vps_logs.py" "$ROOT/run_logs/latest" "$ROOT/run_logs/latest_utf8" >/dev/null 2>&1 || true

echo "$LATEST_NAME" > "$STATE_FILE"

BOT_NAME="${BOT_NAME:-auto}"
BRANCH="${BRANCH:-vps}"

python3 "$ROOT/scripts/summarize_run.py" "$ROOT/run_logs/latest" "$BOT_NAME" "$BRANCH" > "$ROOT/run_logs/latest/summary.json"
vps_scp "$ROOT/scripts/vps_snapshot.ps1" "$VPS_USER@$VPS_HOST:$VPS_PATH/scripts/vps_snapshot.ps1"
vps_ssh "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& '$VPS_PATH/scripts/vps_snapshot.ps1'\"" > "$ROOT/run_logs/latest/vps_snapshot.json"
python3 "$ROOT/scripts/render_dashboard.py" "$ROOT/run_logs/latest/summary.json" "$ROOT/run_logs/latest/vps_snapshot.json" "$ROOT/dashboard/index.html" >/dev/null 2>&1 || true
python3 "$ROOT/scripts/autoupdate_context.py" "$ROOT/RUN_CONTEXT.md" "$ROOT/run_logs/latest/summary.json" >/dev/null 2>&1 || true

echo "Fetched and summarized $LATEST_NAME"
