$ErrorActionPreference = 'Stop'
$base = 'C:\GoldmineOps\ops_motherboard'
New-Item -ItemType Directory -Path $base -Force | Out-Null

Write-Host 'Creating startup task...'
$taskName = 'Goldmine_Ops_Motherboard_24x7'
$cmd = 'cmd /c cd /d C:\GoldmineOps\ops_motherboard && set DISCORD_METRICS_URL=https://discord-gpt-bot-production-4cb9.up.railway.app/metrics && set TELEGRAM_CONTROL_ENABLED=true && set TELEGRAM_CONTROL_CHAT_IDS=2093349528 && set TELEGRAM_CONTROL_POLL_MS=4000 && set TELEGRAM_CONTROL_ALLOW_SHARED_BOT=false && node server.js >> C:\GoldmineOps\reports\ops-motherboard.log 2>&1'

schtasks /Create /TN $taskName /SC ONSTART /RU SYSTEM /TR $cmd /F | Out-Null
schtasks /Run /TN $taskName | Out-Null

Write-Host 'Creating telemetry collector task...'
$telemetryTask = 'Goldmine_MT5_Telemetry_24x7'
$telemetryCmd = 'cmd /c cd /d C:\GoldmineOps\ops_motherboard && set TELEMETRY_DAY_RESET_HOUR_PERTH=7 && node collect_telemetry.mjs >> C:\GoldmineOps\reports\mt5-telemetry.log 2>&1'
schtasks /Create /TN $telemetryTask /SC MINUTE /MO 1 /RU SYSTEM /TR $telemetryCmd /F | Out-Null
schtasks /Run /TN $telemetryTask | Out-Null

Write-Host 'Creating 5-second MT5 live probe loop task...'
$probeTask = 'Goldmine_MT5_LiveProbe_5s'
$probeCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\GoldmineOps\ops_motherboard\run_mt5_live_probe_loop.ps1 >> C:\GoldmineOps\reports\mt5-live-probe.log 2>&1'
schtasks /Create /TN $probeTask /SC ONSTART /RU SYSTEM /TR $probeCmd /F | Out-Null
schtasks /Run /TN $probeTask | Out-Null

Write-Host 'Opening firewall port 8788...'
netsh advfirewall firewall add rule name="Goldmine Ops Motherboard 8788" dir=in action=allow protocol=TCP localport=8788 | Out-Null

Write-Host 'Done. Motherboard + telemetry + live probe tasks created and started.'
Write-Host 'Telegram control expects TELEGRAM_CONTROL_BOT_TOKEN as a dedicated bot token, or TELEGRAM_CONTROL_ALLOW_SHARED_BOT=true if you intentionally want to reuse the OpenClaw bot token.'
