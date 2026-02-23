#!/usr/bin/env bash
set -euo pipefail

# Shared VPS connection defaults + retry helpers.
VPS_HOST="${VPS_HOST:-217.15.164.104}"
VPS_USER="${VPS_USER:-administrator}"
VPS_PATH="${VPS_PATH:-C:/GoldmineOps}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/vps_mt5_auto}"

SSH_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
)

SCP_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
)

retry() {
  local max=3
  local delay=2
  local n=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ $n -ge $max ]]; then
      return 1
    fi
    sleep $delay
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

vps_ssh() {
  retry ssh "${SSH_OPTS[@]}" "$VPS_USER@$VPS_HOST" "$@"
}

vps_scp() {
  retry scp "${SCP_OPTS[@]}" "$@"
}
