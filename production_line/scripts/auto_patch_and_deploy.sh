#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/.."
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[auto] not a git repo, skip"
  exit 0
fi

# Only act if we are on mac-production-line branch
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "mac-production-line" ]]; then
  echo "[auto] branch=$branch (skip auto patch)"
  exit 0
fi

# Only act if repo is clean before patch
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "[auto] repo not clean, skip auto patch"
  exit 0
fi

# Run patcher
pushd "$ROOT" >/dev/null
python3 "$ROOT/scripts/auto_patch_sell_logic.py"
# Normalize logs (no-op if already handled)
python3 "$ROOT/scripts/normalize_vps_logs.py" "$ROOT/run_logs/latest" "$ROOT/run_logs/latest_utf8" >/dev/null 2>&1 || true
popd >/dev/null

# If nothing changed, exit
if git diff --quiet; then
  echo "[auto] no changes to commit"
  exit 0
fi

git add \
  "$ROOT/../bots_full" \
  "$ROOT/../bots_src" \
  "$ROOT/scripts/auto_patch_sell_logic.py" \
  "$ROOT/scripts/auto_patch_and_deploy.sh" \
  "$ROOT/scripts/autonomous_tick.sh" \
  "$ROOT/scripts/fetch_latest_vps_report.sh" \
  "$ROOT/scripts/normalize_vps_logs.py" \
  "$ROOT/scripts/vps_health.sh" \
  "$ROOT/scripts/vps_env.sh" \
  "$ROOT/scripts/install_autonomous_mac.sh" \
  "$ROOT/scripts/deploy_to_vps.sh" \
  "$ROOT/RESET_START_PROMPT.md" \
  "$ROOT/../ops_motherboard_vps/server.js" \
  "$ROOT/../AGENTS.md"

git -c user.name="OpenClaw Auto" -c user.email="openclaw@local" commit -m "auto: apply BE/OPP sell-side rules"

git push origin "$branch"

SKIP_PUSH=1 "$ROOT/scripts/deploy_to_vps.sh" "$branch"
