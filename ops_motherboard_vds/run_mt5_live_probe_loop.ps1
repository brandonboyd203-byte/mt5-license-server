$ErrorActionPreference = 'Continue'
$scriptPath = 'C:\GoldmineOps\ops_motherboard\mt5_live_probe.py'

# Prevent duplicate loop processes.
$me = [System.Diagnostics.Process]::GetCurrentProcess().Id
$existing = Get-CimInstance Win32_Process -Filter "name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match 'run_mt5_live_probe_loop\.ps1' }
if ($existing) {
  Write-Host "mt5 probe loop already running"
  exit 0
}

$pyCandidates = @(
  'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\python.exe',
  'py',
  'python'
)

$pythonExe = $null
foreach ($c in $pyCandidates) {
  try {
    if ($c -match '^[A-Za-z]:\\') {
      if (Test-Path $c) { $pythonExe = $c; break }
    } else {
      $cmd = Get-Command $c -ErrorAction SilentlyContinue
      if ($cmd) { $pythonExe = $c; break }
    }
  } catch {}
}

if (-not $pythonExe) {
  Write-Host 'No Python runtime found for mt5_live_probe loop.'
  exit 1
}

Write-Host "Starting mt5 live probe loop with: $pythonExe"
while ($true) {
  try {
    & $pythonExe $scriptPath
  } catch {
    Write-Host "probe error: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 5
}
