# Overnight apply/verify commands (VDS)

## 1) Compile EDGE / SURGE / DOMINION on VDS (MetaEditor CLI)

```powershell
$mt5 = 'C:\MT5\Lab\metaeditor64.exe'
& $mt5 /compile:'C:\MT5\Lab\MQL5\Experts\GoldmineEdge_Gold_VPS.mq5' /log:'C:\GoldmineOps\reports\compile_edge.log'
& $mt5 /compile:'C:\MT5\Lab\MQL5\Experts\GoldmineSurge_Gold_VPS.mq5' /log:'C:\GoldmineOps\reports\compile_surge.log'
& $mt5 /compile:'C:\MT5\Lab\MQL5\Experts\GoldmineDominion_VPS.mq5' /log:'C:\GoldmineOps\reports\compile_dominion.log'
Get-Content C:\GoldmineOps\reports\compile_edge.log -Tail 40
Get-Content C:\GoldmineOps\reports\compile_surge.log -Tail 40
Get-Content C:\GoldmineOps\reports\compile_dominion.log -Tail 40
```

## 2) Attach/restart profile tasks (EDGE/SURGE/DOMINION)

```powershell
$targets = 'MT5_Edge','MT5_Lab','MT5_Dominion'
foreach($t in $targets){ schtasks /Run /TN $t | Out-Host }
Start-Sleep -Seconds 10
Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object Id,StartTime,CPU | Format-Table -AutoSize
```

## 3) Runtime verification signals (BE/TP/SL + no counter-trades)

```powershell
$log = 'C:\GoldmineOps\reports\ops-motherboard.log'
Select-String -Path $log -Pattern '\[BUY_BE_SET\]|\[SELL_BE_SET\]|TP1|TP2|TP3|TP4|SL|counter-position disabled|Opposite entries live safety switch' |
  Select-Object -Last 120 | ForEach-Object { $_.Line }
```

## 4) Website/live feed checks

```bash
curl -fsS http://46.250.244.188:8788/api/status | jq '.generatedAt, .telemetry.generatedAt'
curl -fsS http://46.250.244.188:8788/api/feed?limit=10 | jq '.count, .feed[0]'
curl -fsS http://46.250.244.188:8788/api/charts/live?symbols=XAUUSD,XAGUSD\&limit=180 | jq '.charts[].count'
```

## 5) Watchdog checks/recovery

```bash
./production_line/scripts/vds_control_live.sh watchdog-check
./production_line/scripts/vds_control_live.sh watchdog-recover
```

## 6) Suggested cron (Mac operator host)

```cron
*/2 * * * * cd /Users/brandonboyd/.openclaw/workspace && ./production_line/scripts/vds_control_live.sh watchdog-check >> production_line/run_logs/watchdog_vds.log 2>&1
*/5 * * * * cd /Users/brandonboyd/.openclaw/workspace && ./production_line/scripts/vds_control_live.sh watchdog-recover >> production_line/run_logs/watchdog_vds_recover.log 2>&1
```
