#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=production_line/scripts/vps_env.sh
source "$ROOT/scripts/vps_env.sh"

echo "[1/3] SSH ping"
vps_ssh "powershell -NoProfile -Command \"Write-Host 'ok'\"" >/dev/null
echo "ok"

echo "[2/3] Motherboard fast-status"
curl -s --max-time 8 "http://$VPS_HOST:8788/api/fast-status" | head -n 5

echo "[3/3] Motherboard status (full, may be slower)"
curl -s --max-time 20 "http://$VPS_HOST:8788/api/status" | head -n 5
