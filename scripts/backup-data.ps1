#requires -Version 5
<#
  Backup Hermes runtime data from the Blaxel sandbox to a local file.
  -------------------------------------------------------------------
  The free tier has NO persistent volume, so a full `bl deploy` rebuild resets the
  sandbox overlay - wiping /root/.hermes runtime data (chat sessions, memories, kanban,
  learned state). Run this BEFORE a rebuild, then restore-data.ps1 AFTER, to preserve it.

  Transport: tar+gzip the important paths inside the box → base64 over the process API →
  decode to backups/hermes-data-<timestamp>.tar.gz locally. (Data is small; base64 over
  stdout is reliable for this size.)

  Usage:  ./scripts/backup-data.ps1
#>
param([string]$OutDir = (Join-Path $PSScriptRoot '..\backups'))
$ErrorActionPreference = 'Stop'
$bl = Join-Path $env:LOCALAPPDATA 'blaxel\bl.exe'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ts  = (Get-Date).ToString('yyyyMMdd-HHmmss')
$out = Join-Path $OutDir "hermes-data-$ts.tar.gz"

# Paths worth preserving (skip regenerable caches: models_dev_cache, skills, image_cache).
$inner = 'cd /root/.hermes 2>/dev/null && tar czf - sessions memories cron state.db state.db-wal state.db-shm kanban.db SOUL.md 2>/dev/null | base64 -w0'
$b64cmd = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inner))
$payload = '{"command":"echo ' + $b64cmd + ' | base64 -d | bash","waitForCompletion":true}'

Write-Host "Backing up /root/.hermes data from sandbox..."
$raw = & $bl run sandbox hermes-box --path /process --data $payload 2>&1 | Out-String
$obj = $raw | ConvertFrom-Json
$data = ($obj.stdout, $obj.logs | Where-Object { $_ } | Select-Object -First 1).Trim()
if (-not $data) { throw "No data returned from sandbox. Raw: $raw" }

[IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($data))
$kb = [Math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "✓ Saved $out ($kb KB)"
Write-Host "  Restore later with: ./scripts/restore-data.ps1 -InFile `"$out`""
