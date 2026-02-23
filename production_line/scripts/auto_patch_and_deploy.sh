#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[auto] patch start"
python3 "$ROOT/scripts/auto_patch_sell_logic.py"

cd "$ROOT/.."

if git diff --quiet; then
  echo "[auto] no changes to commit"
  exit 0
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "[auto] committing to $branch"
git add \
  "$ROOT/../bots_full/GoldmineFresh_Gold.mq5" \
  "$ROOT/../bots_full/GoldmineFresh_Gold_VPS.mq5" \
  "$ROOT/../bots_full/GoldmineBlueprint_Gold.mq5" \
  "$ROOT/../bots_full/GoldmineBlueprint_Gold_VPS.mq5" \
  "$ROOT/../bots_src/GoldmineFresh_Gold.mq5" \
  "$ROOT/scripts/auto_patch_sell_logic.py" \
  "$ROOT/scripts/auto_patch_and_deploy.sh" \
  "$ROOT/scripts/autonomous_tick.sh" \
  "$ROOT/scripts/fetch_latest_vps_report.sh" \
  "$ROOT/scripts/normalize_vps_logs.py" \
  "$ROOT/scripts/vps_health.sh" \
  "$ROOT/scripts/vps_env.sh" \
  "$ROOT/scripts/install_autonomous_mac.sh" \
  "$ROOT/scripts/deploy_to_vps.sh" \
  "$ROOT/../ops_motherboard_vps/server.js"

git -c user.name="OpenClaw Auto" -c user.email="openclaw@local" commit -m "auto: enforce BE=25 for Fresh/Blueprint"

echo "[auto] deploy to VPS"
SKIP_PUSH=1 "$ROOT/scripts/deploy_to_vps.sh" "$branch"
echo "[auto] done"
