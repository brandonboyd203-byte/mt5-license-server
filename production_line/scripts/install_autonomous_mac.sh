#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.openclaw.vps_autorun.plist"
SCRIPT="/Users/brandonboyd/.openclaw/workspace/production_line/scripts/autonomous_tick.sh"
LOG="/Users/brandonboyd/.openclaw/workspace/production_line/run_logs/auto_loop.log"
ERR="/Users/brandonboyd/.openclaw/workspace/production_line/run_logs/auto_loop.err"

mkdir -p "$(dirname "$LOG")"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.openclaw.vps_autorun</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${SCRIPT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${ERR}</string>
  </dict>
</plist>
PLIST

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"

echo "Installed: $PLIST"
