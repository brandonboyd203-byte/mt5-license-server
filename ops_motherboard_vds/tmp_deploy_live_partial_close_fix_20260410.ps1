$ErrorActionPreference = 'Stop'

$branch = 'codex/vds-rebuild-20260409'
$baseRaw = "https://raw.githubusercontent.com/brandonboyd203-byte/mt5-license-server/$branch"
$patchRoot = 'C:\GoldmineOps\ops_motherboard\bot_patches'
$reports = 'C:\GoldmineOps\reports'

New-Item -ItemType Directory -Force -Path $patchRoot | Out-Null
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$sources = @(
  'bots_full/GoldmineBlueprint_Gold_VPS.mq5',
  'bots_full/GoldmineBlueprint_Silver_VPS.mq5',
  'bots_full/GoldmineNexus_Gold_VPS.mq5',
  'bots_full/GoldmineNexus_Silver_VPS.mq5'
)

foreach($src in $sources) {
  $fileName = Split-Path $src -Leaf
  $dst = Join-Path $patchRoot $fileName
  $url = "$baseRaw/$src"
  Write-Host "Downloading $url"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst
  if(!(Test-Path $dst)) { throw "Download failed: $url" }
}

$roots = Get-ChildItem 'C:\MT5' -Directory | Where-Object { $_.Name -match 'BLUEPRINT|NEXUS' }
Write-Host "Found profiles:" ($roots.Name -join ', ')

$maps = @(
  @{ dst='GoldmineBlueprint_Gold.mq5'; src='GoldmineBlueprint_Gold_VPS.mq5' },
  @{ dst='GoldmineBlueprint_Gold_VPS.mq5'; src='GoldmineBlueprint_Gold_VPS.mq5' },
  @{ dst='GoldmineBlueprint_Silver.mq5'; src='GoldmineBlueprint_Silver_VPS.mq5' },
  @{ dst='GoldmineBlueprint_Silver_VPS.mq5'; src='GoldmineBlueprint_Silver_VPS.mq5' },
  @{ dst='GoldmineNexus_Gold.mq5'; src='GoldmineNexus_Gold_VPS.mq5' },
  @{ dst='GoldmineNexus_Gold_VPS.mq5'; src='GoldmineNexus_Gold_VPS.mq5' },
  @{ dst='GoldmineNexus_Silver.mq5'; src='GoldmineNexus_Silver_VPS.mq5' },
  @{ dst='GoldmineNexus_Silver_VPS.mq5'; src='GoldmineNexus_Silver_VPS.mq5' }
)

$compiled = @()
foreach($r in $roots) {
  $editor = Join-Path $r.FullName 'metaeditor64.exe'
  $mqlRoot = Join-Path $r.FullName 'MQL5'
  $experts = Join-Path $mqlRoot 'Experts'

  if(!(Test-Path $editor) -or !(Test-Path $experts)) {
    Write-Warning "skip $($r.Name): missing metaeditor64.exe or experts path"
    continue
  }

  foreach($m in $maps) {
    $dst = Join-Path $experts $m.dst
    if(!(Test-Path $dst)) { continue }

    $src = Join-Path $patchRoot $m.src
    Copy-Item -Path $src -Destination $dst -Force

    $log = Join-Path $reports ("compile_partial_close_fix_" + $r.Name + "_" + ($m.dst -replace '[^a-zA-Z0-9._-]','_') + ".log")
    if(Test-Path $log) { Remove-Item $log -Force }

    Start-Process -FilePath $editor -ArgumentList '/portable', "/compile:$dst", "/include:$mqlRoot", "/log:$log" -Wait | Out-Null
    $logTxt = if(Test-Path $log) { Get-Content $log -Raw } else { '' }
    $ok = ($logTxt -match 'Result:\s*0 errors,\s*0 warnings')
    $compiled += [pscustomobject]@{ profile=$r.Name; file=$m.dst; ok=$ok; log=$log }
    if(-not $ok) {
      Write-Host $logTxt
      throw "Compile failed for $($r.Name) -> $($m.dst)"
    }
  }
}

$tasks = @(
  'MT5_BLUEPRINT_GOLD',
  'MT5_BLUEPRINT_GOLD_SILVER',
  'MT5_BLUEPRINT_GOLD_SILVER20',
  'MT5_BLUEPRINT_SILVER',
  'MT5_NEXUS_GOLD',
  'MT5_NEXUS_GOLD_SILVER',
  'MT5_NEXUS_SILVER'
)

foreach($t in $tasks) {
  try { schtasks /End /TN $t | Out-Null } catch {}
}
Start-Sleep -Seconds 2
foreach($t in $tasks) {
  try {
    schtasks /Run /TN $t | Out-Null
    Write-Host "Restarted task: $t"
  } catch {
    Write-Warning "Failed to restart task: $t"
  }
}

try { schtasks /Run /TN Goldmine_MT5_LiveProbe_5s | Out-Null } catch {}
try { schtasks /Run /TN Goldmine_MT5_Telemetry_24x7 | Out-Null } catch {}
try { schtasks /Run /TN Goldmine_Ops_Motherboard_24x7 | Out-Null } catch {}

$summary = Join-Path $reports 'partial_close_fix_deploy_20260410.json'
$compiled | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $summary
Write-Host "Wrote $summary"
Write-Host 'Deploy complete.'
