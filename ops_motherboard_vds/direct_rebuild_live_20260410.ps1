$ErrorActionPreference = 'Stop'

$Mt5Root = 'C:\MT5'
$SecureRoot = 'C:\GoldmineOps\secure'
$OpsRoot = 'C:\GoldmineOps\ops_motherboard'
$PatchRoot = 'C:\GoldmineOps\ops_motherboard\bot_patches'
$ReportsRoot = 'C:\GoldmineOps\reports'
$Server = 'Exness-MT5Trial7'
$Password = 'Goldmine#26'
$BranchBase = 'https://raw.githubusercontent.com/brandonboyd203-byte/mt5-license-server/codex/vds-rebuild-20260409'

$liveRows = @(
  [pscustomobject]@{ profile='Blueprint_Risk15'; account='433441396'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS+GoldmineBlueprint_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_GOLD_SILVER'; account='433441393'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS+GoldmineBlueprint_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_SILVER'; account='433441392'; server=$Server; password=$Password; bot='GoldmineBlueprint_Silver_VPS'; symbols='XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_GOLD'; account='433441391'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS'; symbols='XAUUSD' },
  [pscustomobject]@{ profile='NEXUS_GOLD_SILVER'; account='433441426'; server=$Server; password=$Password; bot='GoldmineNexus_Gold_VPS+GoldmineNexus_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='NEXUS_SILVER'; account='433441425'; server=$Server; password=$Password; bot='GoldmineNexus_Silver_VPS'; symbols='XAGUSD' },
  [pscustomobject]@{ profile='NEXUS_GOLD'; account='433441422'; server=$Server; password=$Password; bot='GoldmineNexus_Gold_VPS'; symbols='XAUUSD' }
)

$copierProfiles = @('JORDAN','JORDAN4','SARAH','SEAN')
$allowedTasks = @($liveRows | ForEach-Object { 'MT5_' + $_.profile }) + @($copierProfiles | ForEach-Object { 'MT5_' + $_ })

function Ensure-Dir([string]$Path) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-LiveIni([string]$Path, [string]$Account, [string]$Pass, [string]$ServerName, [int]$EnableAutoTrading) {
  $content = @"
[Common]
Login=$Account
Password=$Pass
Server=$ServerName
KeepPrivate=0
ProxyEnable=0
EnableAutoTrading=$EnableAutoTrading

[Charts]
ProfileLast=Default

[Experts]
Enabled=1
AllowDllImport=1
AllowLiveTrading=$EnableAutoTrading
"@
  Set-Content -Path $Path -Value $content -Encoding ASCII
}

function Set-KeyValue([string]$Path, [string]$Key, [string]$Value) {
  $raw = if (Test-Path $Path) { Get-Content $Path -Raw -ErrorAction SilentlyContinue } else { '' }
  if (-not $raw) { $raw = "[Common]`r`n" }
  if ($raw -match "(?m)^$([regex]::Escape($Key))=") {
    $raw = [regex]::Replace($raw, "(?m)^$([regex]::Escape($Key))=.*$", "$Key=$Value")
  } else {
    $raw = $raw.TrimEnd() + "`r`n$Key=$Value`r`n"
  }
  Set-Content -Path $Path -Value $raw -Encoding ASCII
}

function Create-Launcher([string]$Profile, [string]$Account, [string]$Pass, [string]$ServerName) {
  $root = Join-Path $Mt5Root $Profile
  $term = Join-Path $root 'terminal64.exe'
  $startup = Join-Path $root 'config\startup_login.ini'
  $launcher = Join-Path $root 'run_terminal.cmd'
  $lines = @(
    '@echo off',
    ('start "" "' + $term + '" /portable /profile:Default /config:"' + $startup + '" /login:' + $Account + ' /password:' + $Pass + ' /server:' + $ServerName)
  )
  Set-Content -Path $launcher -Value $lines -Encoding ASCII
  return $launcher
}

function Rebuild-Task([string]$Profile, [string]$Launcher) {
  $taskName = 'MT5_' + $Profile
  $runCmd = 'cmd /c "' + $Launcher + '"'
  try { schtasks /Delete /TN $taskName /F | Out-Null } catch {}
  try { schtasks /Delete /TN ($taskName + '_SYS') /F | Out-Null } catch {}
  schtasks /Create /TN $taskName /SC ONLOGON /RL HIGHEST /RU Administrator /IT /TR $runCmd /F | Out-Host
  schtasks /Create /TN ($taskName + '_SYS') /SC ONSTART /RL HIGHEST /RU SYSTEM /TR $runCmd /F | Out-Host
}

function Copy-Patch([string]$Profile, [string]$Name) {
  $experts = Join-Path $Mt5Root ($Profile + '\MQL5\Experts')
  if (!(Test-Path $experts)) { return }
  Copy-Item (Join-Path $PatchRoot $Name) (Join-Path $experts $Name) -Force
}

function Invoke-Compile([string]$Editor, [string]$Source, [string]$LogPath) {
  if (!(Test-Path $Source)) { throw "Missing source file: $Source" }
  if (Test-Path $LogPath) { Remove-Item $LogPath -Force }
  Start-Process -FilePath $Editor -ArgumentList "/compile:$Source", "/log:$LogPath" -Wait | Out-Null
  $txt = if (Test-Path $LogPath) { Get-Content $LogPath -Raw } else { '' }
  Write-Host $txt
  if ($txt -notmatch 'Result:\s*0 errors,\s*0 warnings') {
    throw "Compile failed: $Source"
  }
}

Ensure-Dir $SecureRoot
Ensure-Dir $OpsRoot
Ensure-Dir $PatchRoot
Ensure-Dir $ReportsRoot

$downloads = @{
  'server.js'='ops_motherboard_vds/server.js';
  'collect_telemetry.mjs'='ops_motherboard_vds/collect_telemetry.mjs';
  'mt5_live_probe.py'='ops_motherboard_vds/mt5_live_probe.py';
  'install_vps_motherboard.ps1'='ops_motherboard_vds/install_vps_motherboard.ps1';
  'GoldmineBlueprint_Gold_VPS.mq5'='bots_full/GoldmineBlueprint_Gold_VPS.mq5';
  'GoldmineBlueprint_Silver_VPS.mq5'='bots_full/GoldmineBlueprint_Silver_VPS.mq5';
  'GoldmineNexus_Gold_VPS.mq5'='bots_full/GoldmineNexus_Gold_VPS.mq5';
  'GoldmineNexus_Silver_VPS.mq5'='bots_full/GoldmineNexus_Silver_VPS.mq5';
}

foreach ($name in $downloads.Keys) {
  $rel = $downloads[$name]
  $dest = if ($name -like '*.mq5') { Join-Path $PatchRoot $name } else { Join-Path $OpsRoot $name }
  Invoke-WebRequest -UseBasicParsing -Uri ($BranchBase + '/' + $rel) -OutFile $dest
  Write-Host ('DOWNLOADED ' + $dest)
}

Invoke-WebRequest -UseBasicParsing -Uri ($BranchBase + '/ops_motherboard_vds/run_mt5_live_probe_loop.ps1') -OutFile (Join-Path $OpsRoot 'run_mt5_live_probe_loop.ps1')
Write-Host ('DOWNLOADED ' + (Join-Path $OpsRoot 'run_mt5_live_probe_loop.ps1'))

$liveRows |
  Select-Object profile, account, server, password, @{ n='investor_password'; e={ '' } }, @{ n='label'; e={ $_.profile } } |
  Export-Csv -Path (Join-Path $SecureRoot 'demo_accounts.csv') -NoTypeInformation
$liveRows |
  Select-Object profile, account, server, password, bot, symbols |
  Export-Csv -Path (Join-Path $SecureRoot 'vds_accounts.csv') -NoTypeInformation

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

foreach ($task in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MT5_*' } | Select-Object -ExpandProperty TaskName)) {
  if ($allowedTasks -notcontains $task) {
    try { schtasks /End /TN $task | Out-Null } catch {}
    try { schtasks /Change /TN $task /DISABLE | Out-Null } catch {}
  }
}

foreach ($row in $liveRows) {
  $cfgDir = Join-Path $Mt5Root ($row.profile + '\config')
  Ensure-Dir $cfgDir
  Write-LiveIni (Join-Path $cfgDir 'startup_login.ini') $row.account $row.password $row.server 1
  Write-LiveIni (Join-Path $cfgDir 'common.ini') $row.account $row.password $row.server 1
  $launcher = Create-Launcher $row.profile $row.account $row.password $row.server
  Rebuild-Task $row.profile $launcher
}

foreach ($profile in $copierProfiles) {
  $cfgDir = Join-Path $Mt5Root ($profile + '\config')
  foreach ($ini in @((Join-Path $cfgDir 'startup_login.ini'), (Join-Path $cfgDir 'common.ini'))) {
    if (Test-Path $ini) {
      Set-KeyValue $ini 'EnableAutoTrading' '0'
      Set-KeyValue $ini 'AllowLiveTrading' '0'
      Set-KeyValue $ini 'Enabled' '1'
    }
  }
  try { schtasks /Change /TN ('MT5_' + $profile) /ENABLE | Out-Null } catch {}
}

$blueprintProfiles = @('Blueprint_Risk15','BLUEPRINT_GOLD_SILVER','BLUEPRINT_SILVER','BLUEPRINT_GOLD')
$nexusProfiles = @('NEXUS_GOLD_SILVER','NEXUS_SILVER','NEXUS_GOLD')

foreach ($profile in $blueprintProfiles) {
  Copy-Patch $profile 'GoldmineBlueprint_Gold_VPS.mq5'
  Copy-Patch $profile 'GoldmineBlueprint_Silver_VPS.mq5'
}

foreach ($profile in $nexusProfiles) {
  Copy-Patch $profile 'GoldmineNexus_Gold_VPS.mq5'
  Copy-Patch $profile 'GoldmineNexus_Silver_VPS.mq5'
}

$bpEditor = 'C:\MT5\BLUEPRINT_GOLD\metaeditor64.exe'
$bpExperts = 'C:\MT5\BLUEPRINT_GOLD\MQL5\Experts'
if (Test-Path $bpEditor) {
  Invoke-Compile $bpEditor (Join-Path $bpExperts 'GoldmineBlueprint_Gold_VPS.mq5') (Join-Path $ReportsRoot 'compile_blueprint_gold_vps_20260410.log')
  Invoke-Compile $bpEditor (Join-Path $bpExperts 'GoldmineBlueprint_Silver_VPS.mq5') (Join-Path $ReportsRoot 'compile_blueprint_silver_vps_20260410.log')
  foreach ($profile in $blueprintProfiles) {
    $experts = Join-Path $Mt5Root ($profile + '\MQL5\Experts')
    if (Test-Path $experts) {
      Copy-Item (Join-Path $bpExperts 'GoldmineBlueprint_Gold_VPS.ex5') (Join-Path $experts 'GoldmineBlueprint_Gold_VPS.ex5') -Force
      Copy-Item (Join-Path $bpExperts 'GoldmineBlueprint_Silver_VPS.ex5') (Join-Path $experts 'GoldmineBlueprint_Silver_VPS.ex5') -Force
    }
  }
}

$nxEditor = 'C:\MT5\NEXUS_GOLD\metaeditor64.exe'
$nxExperts = 'C:\MT5\NEXUS_GOLD\MQL5\Experts'
if (Test-Path $nxEditor) {
  Invoke-Compile $nxEditor (Join-Path $nxExperts 'GoldmineNexus_Gold_VPS.mq5') (Join-Path $ReportsRoot 'compile_nexus_gold_vps_20260410.log')
  Invoke-Compile $nxEditor (Join-Path $nxExperts 'GoldmineNexus_Silver_VPS.mq5') (Join-Path $ReportsRoot 'compile_nexus_silver_vps_20260410.log')
  foreach ($profile in $nexusProfiles) {
    $experts = Join-Path $Mt5Root ($profile + '\MQL5\Experts')
    if (Test-Path $experts) {
      Copy-Item (Join-Path $nxExperts 'GoldmineNexus_Gold_VPS.ex5') (Join-Path $experts 'GoldmineNexus_Gold_VPS.ex5') -Force
      Copy-Item (Join-Path $nxExperts 'GoldmineNexus_Silver_VPS.ex5') (Join-Path $experts 'GoldmineNexus_Silver_VPS.ex5') -Force
    }
  }
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OpsRoot 'install_vps_motherboard.ps1')

foreach ($task in $allowedTasks) {
  try { schtasks /Change /TN $task /ENABLE | Out-Null } catch {}
  try { schtasks /End /TN $task | Out-Null } catch {}
  Start-Sleep -Milliseconds 200
  try { schtasks /Run /TN $task | Out-Null } catch {}
}

try { schtasks /Run /TN Goldmine_MT5_LiveProbe_5s | Out-Null } catch {}
try { schtasks /Run /TN Goldmine_MT5_Telemetry_24x7 | Out-Null } catch {}
try { schtasks /Run /TN Goldmine_Ops_Motherboard_24x7 | Out-Null } catch {}

Write-Host 'DIRECT_REBUILD_DONE'
