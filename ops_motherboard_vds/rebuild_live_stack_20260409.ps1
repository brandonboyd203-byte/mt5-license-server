$ErrorActionPreference = 'Stop'

$Mt5Root = 'C:\MT5'
$SecureRoot = 'C:\GoldmineOps\secure'
$PatchRoot = 'C:\GoldmineOps\ops_motherboard\bot_patches'
$OpsRoot = 'C:\GoldmineOps\ops_motherboard'
$ReportsRoot = 'C:\GoldmineOps\reports'
$Server = 'Exness-MT5Trial7'
$Password = 'Goldmine#26'

$liveRows = @(
  [pscustomobject]@{ profile='Blueprint_Risk15';       account='433441396'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS+GoldmineBlueprint_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_GOLD_SILVER';  account='433441393'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS+GoldmineBlueprint_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_SILVER';       account='433441392'; server=$Server; password=$Password; bot='GoldmineBlueprint_Silver_VPS'; symbols='XAGUSD' },
  [pscustomobject]@{ profile='BLUEPRINT_GOLD';         account='433441391'; server=$Server; password=$Password; bot='GoldmineBlueprint_Gold_VPS'; symbols='XAUUSD' },
  [pscustomobject]@{ profile='NEXUS_GOLD_SILVER';      account='433441426'; server=$Server; password=$Password; bot='GoldmineNexus_Gold_VPS+GoldmineNexus_Silver_VPS'; symbols='XAUUSD+XAGUSD' },
  [pscustomobject]@{ profile='NEXUS_SILVER';           account='433441425'; server=$Server; password=$Password; bot='GoldmineNexus_Silver_VPS'; symbols='XAGUSD' },
  [pscustomobject]@{ profile='NEXUS_GOLD';             account='433441422'; server=$Server; password=$Password; bot='GoldmineNexus_Gold_VPS'; symbols='XAUUSD' }
)

$copierProfiles = @('JORDAN','JORDAN4','SARAH','SEAN')
$allowedProfiles = @($liveRows | ForEach-Object { $_.profile }) + $copierProfiles
$allowedTasks = @($allowedProfiles | ForEach-Object { "MT5_$($_)" })

function Ensure-Dir([string]$Path) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Set-IniSectionValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
  $lines = [System.Collections.Generic.List[string]]::new()
  if (Test-Path $Path) {
    foreach ($line in @(Get-Content $Path -ErrorAction SilentlyContinue)) {
      $lines.Add([string]$line)
    }
  }
  if ($lines.Count -eq 0) {
    $lines.Add("[$Section]")
  }

  $sectionHeader = "[$Section]"
  $sectionStart = -1
  $sectionEnd = $lines.Count
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $sectionHeader) {
      $sectionStart = $i
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j].Trim().StartsWith('[') -and $lines[$j].Trim().EndsWith(']')) {
          $sectionEnd = $j
          break
        }
      }
      break
    }
  }

  if ($sectionStart -lt 0) {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
    $sectionStart = $lines.Count
    $sectionEnd = $lines.Count + 1
    $lines.Add($sectionHeader)
  }

  $set = $false
  for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
    if ($lines[$i].Trim().StartsWith("$Key=")) {
      $lines[$i] = "$Key=$Value"
      $set = $true
      break
    }
  }
  if (-not $set) {
    $insertAt = $sectionEnd
    $lines.Insert($insertAt, "$Key=$Value")
  }

  Set-Content -Path $Path -Value $lines -Encoding ASCII
}

function Set-ProfileCredentials([string]$Profile, [string]$Account, [string]$ServerName, [string]$Pass) {
  $cfgDir = Join-Path $Mt5Root "$Profile\config"
  Ensure-Dir $cfgDir
  $startup = Join-Path $cfgDir 'startup_login.ini'
  $common = Join-Path $cfgDir 'common.ini'

  foreach ($ini in @($startup, $common)) {
    Set-IniSectionValue $ini 'Common' 'Login' $Account
    Set-IniSectionValue $ini 'Common' 'Password' $Pass
    Set-IniSectionValue $ini 'Common' 'Server' $ServerName
    Set-IniSectionValue $ini 'Common' 'KeepPrivate' '0'
    Set-IniSectionValue $ini 'Common' 'ProxyEnable' '0'
    Set-IniSectionValue $ini 'Charts' 'ProfileLast' 'Default'
    Set-IniSectionValue $ini 'Experts' 'Enabled' '1'
    Set-IniSectionValue $ini 'Experts' 'AllowDllImport' '1'
  }
}

function Set-ProfileAutoTrading([string]$Profile, [int]$EnableAutoTrading) {
  $cfgDir = Join-Path $Mt5Root "$Profile\config"
  Ensure-Dir $cfgDir
  foreach ($ini in @((Join-Path $cfgDir 'startup_login.ini'), (Join-Path $cfgDir 'common.ini'))) {
    Set-IniSectionValue $ini 'Common' 'EnableAutoTrading' $EnableAutoTrading
    Set-IniSectionValue $ini 'Experts' 'AllowLiveTrading' $EnableAutoTrading
    Set-IniSectionValue $ini 'Experts' 'Enabled' '1'
  }
}

function Rebuild-Task([string]$Profile, [string]$Account, [string]$ServerName, [string]$Pass) {
  $root = Join-Path $Mt5Root $Profile
  $term = Join-Path $root 'terminal64.exe'
  $startup = Join-Path $root 'config\startup_login.ini'
  if (!(Test-Path $term)) {
    Write-Warning "missing terminal64.exe for $Profile"
    return
  }
  $taskName = "MT5_$Profile"
  $launcher = Join-Path $root 'run_terminal.cmd'
  $launcherLines = @(
    '@echo off',
    "start \"\" \"$term\" /portable /profile:Default /config:\"$startup\" /login:$Account /password:$Pass /server:$ServerName"
  )
  Set-Content -Path $launcher -Value $launcherLines -Encoding ASCII
  $runCmd = "cmd /c \"$launcher\""
  schtasks /Delete /TN $taskName /F | Out-Null
  schtasks /Delete /TN "${taskName}_SYS" /F | Out-Null
  schtasks /Create /TN $taskName /SC ONLOGON /RL HIGHEST /RU Administrator /IT /TR $runCmd /F | Out-Host
  schtasks /Create /TN "${taskName}_SYS" /SC ONSTART /RL HIGHEST /RU SYSTEM /TR $runCmd /F | Out-Host
}

function Disable-TaskSafe([string]$TaskName) {
  try { schtasks /End /TN $TaskName | Out-Null } catch {}
  try { schtasks /Change /TN $TaskName /DISABLE | Out-Null } catch {}
}

function Enable-TaskSafe([string]$TaskName) {
  try { schtasks /Change /TN $TaskName /ENABLE | Out-Null } catch {}
}

function Invoke-Compile([string]$Editor, [string]$Source, [string]$LogPath) {
  if (!(Test-Path $Source)) { throw "Missing source file: $Source" }
  if (Test-Path $LogPath) { Remove-Item $LogPath -Force }
  Start-Process -FilePath $Editor -ArgumentList "/compile:$Source", "/log:$LogPath" -Wait | Out-Null
  $txt = if (Test-Path $LogPath) { Get-Content $LogPath -Raw } else { '' }
  if ($txt -notmatch 'Result:\s*0 errors,\s*0 warnings') {
    Write-Host $txt
    throw "Compile failed: $Source"
  }
}

Ensure-Dir $SecureRoot
Ensure-Dir $ReportsRoot

$demoCsv = Join-Path $SecureRoot 'demo_accounts.csv'
$vdsCsv = Join-Path $SecureRoot 'vds_accounts.csv'
$liveRows |
  Select-Object profile, account, server, password, @{ n='investor_password'; e={ '' } }, @{ n='label'; e={ $_.profile } } |
  Export-Csv -Path $demoCsv -NoTypeInformation
$liveRows |
  Select-Object profile, account, server, password, bot, symbols |
  Export-Csv -Path $vdsCsv -NoTypeInformation

Write-Host "Wrote account maps:"
Write-Host "  $demoCsv"
Write-Host "  $vdsCsv"

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

foreach ($task in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MT5_*' } | Select-Object -ExpandProperty TaskName)) {
  if ($allowedTasks -notcontains $task) {
    Disable-TaskSafe $task
    Write-Host "Disabled inactive MT5 task: $task"
  }
}

foreach ($row in $liveRows) {
  Set-ProfileCredentials -Profile $row.profile -Account $row.account -ServerName $row.server -Pass $row.password
  Set-ProfileAutoTrading -Profile $row.profile -EnableAutoTrading 1
  Rebuild-Task -Profile $row.profile -Account $row.account -ServerName $row.server -Pass $row.password
  Enable-TaskSafe -TaskName ("MT5_" + $row.profile)
}

foreach ($profile in $copierProfiles) {
  if (Test-Path (Join-Path $Mt5Root $profile)) {
    Set-ProfileAutoTrading -Profile $profile -EnableAutoTrading 0
    Enable-TaskSafe -TaskName ("MT5_" + $profile)
    Write-Host "Copier kept open with algo OFF: $profile"
  }
}

$blueprintProfiles = @('Blueprint_Risk15','BLUEPRINT_GOLD_SILVER','BLUEPRINT_SILVER','BLUEPRINT_GOLD')
$nexusProfiles = @('NEXUS_GOLD_SILVER','NEXUS_SILVER','NEXUS_GOLD')

$bpGoldMq5 = Join-Path $PatchRoot 'GoldmineBlueprint_Gold_VPS.mq5'
$bpSilverMq5 = Join-Path $PatchRoot 'GoldmineBlueprint_Silver_VPS.mq5'
$nxGoldMq5 = Join-Path $PatchRoot 'GoldmineNexus_Gold_VPS.mq5'
$nxSilverMq5 = Join-Path $PatchRoot 'GoldmineNexus_Silver_VPS.mq5'

if ((Test-Path $bpGoldMq5) -and (Test-Path $bpSilverMq5)) {
  foreach ($profile in $blueprintProfiles) {
    $experts = Join-Path $Mt5Root "$profile\MQL5\Experts"
    if (!(Test-Path $experts)) { continue }
    Copy-Item $bpGoldMq5 (Join-Path $experts 'GoldmineBlueprint_Gold_VPS.mq5') -Force
    if (Test-Path (Join-Path $experts 'GoldmineBlueprint_Gold.mq5')) {
      Copy-Item $bpGoldMq5 (Join-Path $experts 'GoldmineBlueprint_Gold.mq5') -Force
    }
    Copy-Item $bpSilverMq5 (Join-Path $experts 'GoldmineBlueprint_Silver_VPS.mq5') -Force
    if (Test-Path (Join-Path $experts 'GoldmineBlueprint_Silver.mq5')) {
      Copy-Item $bpSilverMq5 (Join-Path $experts 'GoldmineBlueprint_Silver.mq5') -Force
    }
  }
  $bpCompileProfile = if (Test-Path (Join-Path $Mt5Root 'BLUEPRINT_GOLD')) { 'BLUEPRINT_GOLD' } else { 'Blueprint_Risk15' }
  $bpEditor = Join-Path $Mt5Root "$bpCompileProfile\metaeditor64.exe"
  if (Test-Path $bpEditor) {
    $bpExperts = Join-Path $Mt5Root "$bpCompileProfile\MQL5\Experts"
    Invoke-Compile -Editor $bpEditor -Source (Join-Path $bpExperts 'GoldmineBlueprint_Gold_VPS.mq5') -LogPath (Join-Path $ReportsRoot 'compile_blueprint_gold_vps_20260409.log')
    Invoke-Compile -Editor $bpEditor -Source (Join-Path $bpExperts 'GoldmineBlueprint_Silver_VPS.mq5') -LogPath (Join-Path $ReportsRoot 'compile_blueprint_silver_vps_20260409.log')
    foreach ($profile in $blueprintProfiles) {
      $experts = Join-Path $Mt5Root "$profile\MQL5\Experts"
      if (!(Test-Path $experts)) { continue }
      foreach ($file in @('GoldmineBlueprint_Gold_VPS.ex5','GoldmineBlueprint_Silver_VPS.ex5')) {
        $src = Join-Path $bpExperts $file
        if (Test-Path $src) {
          Copy-Item $src (Join-Path $experts $file) -Force
        }
      }
    }
    Write-Host 'Blueprint runtime compiled and distributed.'
  }
}
else {
  Write-Warning 'Blueprint patch mq5 files not found in bot_patches; skipped Blueprint deploy.'
}

if ((Test-Path $nxGoldMq5) -and (Test-Path $nxSilverMq5)) {
  foreach ($profile in $nexusProfiles) {
    $experts = Join-Path $Mt5Root "$profile\MQL5\Experts"
    if (!(Test-Path $experts)) { continue }
    Copy-Item $nxGoldMq5 (Join-Path $experts 'GoldmineNexus_Gold_VPS.mq5') -Force
    Copy-Item $nxSilverMq5 (Join-Path $experts 'GoldmineNexus_Silver_VPS.mq5') -Force
  }
  $nxCompileProfile = if (Test-Path (Join-Path $Mt5Root 'NEXUS_GOLD')) { 'NEXUS_GOLD' } else { 'NEXUS_GOLD_SILVER' }
  $nxEditor = Join-Path $Mt5Root "$nxCompileProfile\metaeditor64.exe"
  if (Test-Path $nxEditor) {
    $nxExperts = Join-Path $Mt5Root "$nxCompileProfile\MQL5\Experts"
    Invoke-Compile -Editor $nxEditor -Source (Join-Path $nxExperts 'GoldmineNexus_Gold_VPS.mq5') -LogPath (Join-Path $ReportsRoot 'compile_nexus_gold_vps_20260409.log')
    Invoke-Compile -Editor $nxEditor -Source (Join-Path $nxExperts 'GoldmineNexus_Silver_VPS.mq5') -LogPath (Join-Path $ReportsRoot 'compile_nexus_silver_vps_20260409.log')
    foreach ($profile in $nexusProfiles) {
      $experts = Join-Path $Mt5Root "$profile\MQL5\Experts"
      if (!(Test-Path $experts)) { continue }
      foreach ($file in @('GoldmineNexus_Gold_VPS.ex5','GoldmineNexus_Silver_VPS.ex5')) {
        $src = Join-Path $nxExperts $file
        if (Test-Path $src) {
          Copy-Item $src (Join-Path $experts $file) -Force
        }
      }
    }
    Write-Host 'Nexus runtime compiled and distributed.'
  }
}
else {
  Write-Warning 'Nexus patch mq5 files not found in bot_patches; skipped Nexus deploy.'
}

foreach ($task in $allowedTasks) {
  try { schtasks /End /TN $task | Out-Null } catch {}
  Start-Sleep -Milliseconds 200
  try { schtasks /Run /TN $task | Out-Null } catch {}
}

if (Test-Path (Join-Path $OpsRoot 'collect_telemetry.mjs')) {
  cmd /c "cd /d $OpsRoot && node collect_telemetry.mjs" | Out-Host
}
try { schtasks /Run /TN Goldmine_MT5_Telemetry_24x7 | Out-Null } catch {}
try { schtasks /Run /TN Goldmine_Ops_Motherboard_24x7 | Out-Null } catch {}

Write-Host 'Live stack rebuild complete.'
