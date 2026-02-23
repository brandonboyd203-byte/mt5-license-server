#!/usr/bin/env bash
set -euo pipefail

# Usage:
# VPS_HOST=1.2.3.4 VPS_USER=Administrator VPS_PATH='C:/GoldmineOps' ./production_line/scripts/deploy_to_vps.sh

BRANCH="${1:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=production_line/scripts/vps_env.sh
source "$ROOT/scripts/vps_env.sh"

if [[ "${SKIP_PUSH:-0}" == "1" ]]; then
  echo "[1/4] Skip push (SKIP_PUSH=1)"
else
  echo "[1/4] Push latest branch: ${BRANCH}"
  git push origin "${BRANCH}"
fi

echo "[2/4] Trigger VPS update"
vps_ssh "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
  if (!(Test-Path '${VPS_PATH}')) { throw 'VPS_PATH missing' }
  Set-Location '${VPS_PATH}'
  git pull origin ${BRANCH}
  if (Test-Path '.\\scripts\\run_all.ps1') {
    .\\scripts\\run_all.ps1
  } else {
    Write-Host 'run_all.ps1 not found; pull succeeded only.'
  }
\""

COPY_REPORTS="${COPY_REPORTS:-0}"

if [[ "$COPY_REPORTS" == "1" ]]; then
  echo "[3/4] Pull latest reports"
  mkdir -p ./production_line/run_logs
  vps_scp -r "${VPS_USER}@${VPS_HOST}:${VPS_PATH}/reports/*" ./production_line/run_logs/ 2>/dev/null || true
else
  echo "[3/4] Skip report copy (set COPY_REPORTS=1 to enable)"
fi

echo "[4/4] Done"
echo "Deploy + run cycle complete."
