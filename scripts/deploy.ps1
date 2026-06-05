#requires -Version 5
<#
  Deploy (or redeploy) the Hermes sandbox from .env - one command.
  ---------------------------------------------------------------
  Reads .env, passes every non-infra key to `bl deploy -s KEY=VALUE`, waits for
  DEPLOYED, then re-binds BOTH previews (a full deploy always breaks them).

  ⚠ A full rebuild WIPES /root/.hermes runtime data (free tier, no volume).
     Run scripts/backup-data.ps1 before, and scripts/restore-data.ps1 after, if you
     care about chat history/memories.

  Usage:
    ./scripts/deploy.ps1                 # full build + deploy + rebind
    ./scripts/deploy.ps1 -SkipBuild      # config-only (faster; restarts container)
#>
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$bl   = Join-Path $env:LOCALAPPDATA 'blaxel\bl.exe'
$root = Split-Path $PSScriptRoot -Parent
$box  = Join-Path $root 'hermes-box'
$envF = Join-Path $root '.env'
if (-not (Test-Path $envF)) { throw ".env not found. Copy .env.example → .env (or run scripts/setup.ps1)." }

# --- parse .env into a map ---
$cfg = @{}
foreach ($line in Get-Content $envF) {
  $t = $line.Trim()
  if (-not $t -or $t.StartsWith('#') -or ($t -notmatch '=')) { continue }
  $k, $v = $t -split '=', 2
  $cfg[$k.Trim()] = $v.Trim()
}

# Container secrets = everything except the BLAXEL_* infra keys; skip blanks.
$secretArgs = @()
foreach ($k in $cfg.Keys) {
  if ($k -like 'BLAXEL_*') { continue }
  if ([string]::IsNullOrWhiteSpace($cfg[$k])) { continue }
  $secretArgs += '-s'; $secretArgs += "$k=$($cfg[$k])"
}

$sandbox = $cfg['BLAXEL_SANDBOX_NAME']; if (-not $sandbox) { $sandbox = 'hermes-box' }

Push-Location $box
try {
  Write-Host "▶ Deploying $sandbox ($($secretArgs.Count/2) secrets)$(if($SkipBuild){' [skip-build]'})..."
  $deployArgs = @('deploy', '--yes', '--name', $sandbox)
  if ($SkipBuild) { $deployArgs += '--skip-build' }
  & $bl @deployArgs @secretArgs
  if ($LASTEXITCODE -ne 0) { throw "bl deploy failed." }

  Write-Host "▶ Waiting for DEPLOYED..."
  $ok = $false
  for ($i = 0; $i -lt 60; $i++) {
    $st = (& $bl get sandbox $sandbox 2>&1 | Out-String)
    if ($st -match 'DEPLOYED') { $ok = $true; break }
    if ($st -match 'FAILED')   { throw "Build FAILED. Run: bl logs sandbox $sandbox" }
    Start-Sleep 12
  }
  if (-not $ok) { throw "Timed out waiting for DEPLOYED." }

  Write-Host "▶ Re-binding previews (generated from .env for sandbox '$sandbox')..."
  $tg     = $cfg['BLAXEL_TELEGRAM_PREVIEW'];  if (-not $tg)     { $tg = 'porttest2' }
  $db     = $cfg['BLAXEL_DASHBOARD_PREVIEW']; if (-not $db)     { $db = 'dashboard' }
  $tgPort = $cfg['TELEGRAM_WEBHOOK_PORT'];    if (-not $tgPort) { $tgPort = '9099' }
  $dbPfx  = $cfg['BLAXEL_DASHBOARD_PREFIX'];  if (-not $dbPfx)  { $dbPfx = $db }

  # Telegram preview (public; URL discovered after creation → no fixed prefix needed).
  $tgF = Join-Path $env:TEMP 'hermes-tg-preview.yaml'
  Set-Content $tgF "kind: Preview`nmetadata:`n  name: $tg`n  resourceName: $sandbox`nspec:`n  port: $tgPort`n  public: true`n" -Encoding ascii
  & $bl delete sandbox $sandbox preview $tg 2>&1 | Out-Null
  & $bl apply -f $tgF 2>&1 | Out-Null

  # Dashboard preview (public; readable URL via prefixUrl) - only if the dashboard is on.
  if ($cfg['HERMES_DASHBOARD_BASIC_AUTH_USERNAME']) {
    $dbF = Join-Path $env:TEMP 'hermes-db-preview.yaml'
    Set-Content $dbF "kind: Preview`nmetadata:`n  name: $db`n  resourceName: $sandbox`nspec:`n  port: 9119`n  public: true`n  prefixUrl: $dbPfx`n" -Encoding ascii
    & $bl delete sandbox $sandbox preview $db 2>&1 | Out-Null
    & $bl apply -f $dbF 2>&1 | Out-Null
  }
  # Verify the telegram preview actually came up (apply above is best-effort/silenced).
  $pv = (& $bl get sandbox $sandbox preview $tg -o yaml 2>&1 | Out-String)
  if ($pv -notmatch '(?m)^\s*url:\s*\S') { throw "Telegram preview '$tg' (port $tgPort) was not created. Check: bl get sandbox $sandbox preview" }
  Write-Host "✓ Deployed and re-bound. Text the bot / open the dashboard to verify."
}
finally { Pop-Location }
