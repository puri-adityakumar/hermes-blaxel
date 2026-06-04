#requires -Version 5
<#
  Restore Hermes runtime data into the Blaxel sandbox from a local backup.
  ----------------------------------------------------------------------
  Run AFTER a `bl deploy` rebuild (which resets the overlay) to put back the data saved
  by backup-data.ps1 - chat sessions, memories, kanban, learned state.

  Transport: base64 the archive, upload in ≤90 KB chunks (Linux caps a single command
  ARG at 128 KB, and Windows caps a CLI arg too - so we append chunks to a staging file
  via `bl run ... --file <payload.json>`), then decode + extract into /root/.hermes.

  Usage:  ./scripts/restore-data.ps1 -InFile .\backups\hermes-data-YYYYMMDD-HHMMSS.tar.gz
#>
param([Parameter(Mandatory)][string]$InFile)
$ErrorActionPreference = 'Stop'
$bl  = Join-Path $env:LOCALAPPDATA 'blaxel\bl.exe'
$tmp = Join-Path $env:TEMP 'hermes-restore-payload.json'
if (-not (Test-Path $InFile)) { throw "Backup file not found: $InFile" }

function Invoke-Box([string]$cmd) {
  $payload = @{ command = $cmd; waitForCompletion = $true } | ConvertTo-Json -Compress
  Set-Content -Path $tmp -Value $payload -Encoding ascii -NoNewline
  return (& $bl run sandbox hermes-box --path /process --file $tmp 2>&1 | Out-String)
}

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($InFile))
$chunk = 90000
$total = [Math]::Ceiling($b64.Length / $chunk)
Write-Host "Restoring $InFile ($([Math]::Round($b64.Length/1KB))KB b64) in $total chunk(s)..."

Invoke-Box ': > /tmp/r.b64' | Out-Null   # truncate staging file
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
  $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
  Invoke-Box "printf '%s' '$part' >> /tmp/r.b64" | Out-Null
  Write-Host ("  {0}/{1}" -f [Math]::Min([Math]::Floor($i/$chunk)+1, $total), $total)
}

$res = Invoke-Box 'base64 -d /tmp/r.b64 > /tmp/restore.tar.gz && tar xzf /tmp/restore.tar.gz -C /root/.hermes && echo RESTORED_OK && du -sh /root/.hermes/sessions 2>/dev/null | cut -f1'
if ($res -match 'RESTORED_OK') { Write-Host "✓ Restored into /root/.hermes" }
else { Write-Host "⚠ Restore may have failed:`n$res" }
Remove-Item $tmp -ErrorAction SilentlyContinue
