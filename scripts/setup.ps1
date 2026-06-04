#requires -Version 5
<#
  Hermes-on-Blaxel setup wizard.
  ------------------------------
  Clone the repo → run this → answer a few prompts → you have a live Telegram bot
  (and optional web dashboard) on a Blaxel sandbox. Idempotent: re-run any time.

  What it does:
    1. Checks prerequisites (Blaxel CLI + login).
    2. Prompts for the few things only you know (provider key, bot token, your TG id).
    3. Generates all random secrets for you.
    4. Deploys, discovers the public webhook URL, wires Telegram to it, verifies.

  Usage:  ./scripts/setup.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$envF = Join-Path $root '.env'
$bl   = Join-Path $env:LOCALAPPDATA 'blaxel\bl.exe'

function Hex([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  -join ($b | ForEach-Object { $_.ToString('x2') })
}
function Ask([string]$prompt, [string]$help, [switch]$Optional) {
  if ($help) { Write-Host "  $help" -ForegroundColor DarkGray }
  while ($true) {
    $v = (Read-Host $prompt).Trim()
    if ($v -or $Optional) { return $v }
    Write-Host "  (required)" -ForegroundColor Yellow
  }
}

Write-Host "`n=== Hermes-on-Blaxel setup ===`n" -ForegroundColor Cyan

# 1. Prerequisites
if (-not (Test-Path $bl)) {
  Write-Host "Blaxel CLI not found. Install it (PowerShell):" -ForegroundColor Yellow
  Write-Host '  irm https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.ps1 | iex'
  throw "Install bl, restart the shell, then re-run."
}
$ws = (& $bl workspaces 2>&1 | Out-String)
if ($ws -notmatch '\*') {
  Write-Host "Not logged in. Run:  & `"$bl`" login" -ForegroundColor Yellow
  throw "Log in first, then re-run."
}
Write-Host "✓ Blaxel CLI ready.`n"

# 2. Reuse existing .env?
if (Test-Path $envF) {
  $ans = Ask "Found an existing .env. Re-deploy with it as-is? (y/n)" "" -Optional
  if ($ans -match '^y') { & (Join-Path $PSScriptRoot 'deploy.ps1'); return }
  Write-Host "Re-running the wizard (will overwrite .env)...`n"
}

# 3. Collect the few human-only inputs
Write-Host "Model provider  [1] Z.AI/GLM  [2] Anthropic  [3] OpenAI  [4] Gemini  [5] configure later in Hermes" -ForegroundColor Cyan
$pSel = Ask "Pick a provider (1-5)" "Not everyone uses Z.AI - pick yours, or 5 to set it up in the dashboard / 'hermes setup model' after deploy" -Optional
$prov=''; $provKeyVar=''; $provKey=''; $provModel=''; $provBase=''
switch ($pSel) {
  '2' { $prov='anthropic'; $provKeyVar='ANTHROPIC_API_KEY'; $provModel='claude-sonnet-4-6' }
  '3' { $prov='openai';    $provKeyVar='OPENAI_API_KEY';    $provModel='gpt-4o' }
  '4' { $prov='gemini';    $provKeyVar='GEMINI_API_KEY';    $provModel='gemini-2.5-pro' }
  '5' { $prov='' }   # bring-your-own: configure provider in Hermes after deploy
  default { $prov='zai'; $provKeyVar='ZAI_API_KEY'; $provModel='glm-5.1' }
}
if ($prov) {
  $provKey = Ask "$prov API key" "Paste your $prov key"
  $m = Ask "Model name [$provModel]" "" -Optional; if ($m) { $provModel = $m }
  if ($prov -eq 'zai') { $cp = Ask "Use Z.AI Coding Plan endpoint? (y/n)" "" -Optional; if ($cp -notmatch '^n') { $provBase='https://api.z.ai/api/coding/paas/v4' } }
}
$tgTok = Ask "Telegram bot token"    "From @BotFather (looks like 123456:ABC...)"
$tgId  = Ask "Your Telegram user id" "From @userinfobot - only this user can chat to the bot"
$wantDash = Ask "Enable the web dashboard? (y/n)" "Adds a username/password admin UI" -Optional
$dashUser = ''
if ($wantDash -match '^y') { $dashUser = Ask "  Dashboard username" "" }
$modeAns = Ask "Run mode: [1] always-on (instant, costs 24/7)  [2] scale-to-zero (cheap, ~1 min wake)" "Pick 2 to save money; 1 for instant replies" -Optional
$mode = if ($modeAns -eq '2') { 'scale-to-zero' } else { 'always-on' }
$sbxName = Ask "Sandbox name [hermes-box]" "Lets you run more than one (e.g. hermes-test)" -Optional
if (-not $sbxName) { $sbxName = 'hermes-box' }

# 4. Generate secrets + assemble config
$cfg = [ordered]@{
  DEPLOY_MODE              = $mode
  TELEGRAM_BOT_TOKEN       = $tgTok
  TELEGRAM_WEBHOOK_URL     = ''                  # filled after first deploy
  TELEGRAM_WEBHOOK_SECRET  = (Hex 32)
  TELEGRAM_WEBHOOK_PORT    = '9099'
  TELEGRAM_ALLOWED_USERS   = $tgId
  TELEGRAM_HOME_CHANNEL    = $tgId
  BLAXEL_SANDBOX_NAME      = $sbxName
  BLAXEL_TELEGRAM_PREVIEW  = "$sbxName-tg"
  BLAXEL_DASHBOARD_PREVIEW = "$sbxName-dash"
  BLAXEL_DASHBOARD_PREFIX  = "$sbxName-dash"     # → dashboard URL <prefix>-<workspace>.preview.bl.run
}
if ($prov) {
  $cfg['MODEL_PROVIDER'] = $prov
  $cfg['MODEL_NAME']     = $provModel
  if ($provBase) { $cfg['MODEL_BASE_URL'] = $provBase }
  $cfg[$provKeyVar]      = $provKey            # provider's standard key var (passed through by entrypoint)
}
$dashPass = ''
if ($dashUser) {
  $dashPass = (Hex 8)  # 16-char hex password
  $cfg['HERMES_DASHBOARD_SESSION_TOKEN']        = (Hex 24)
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_USERNAME']  = $dashUser
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_PASSWORD']  = $dashPass
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_SECRET']    = (Hex 32)
}

function Save-Env {
  $lines = $cfg.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
  Set-Content -Path $envF -Value $lines -Encoding ascii
}
Save-Env
Write-Host "`n✓ Wrote .env (secrets generated).`n"

# 5. First deploy (creates sandbox + telegram preview)
& (Join-Path $PSScriptRoot 'deploy.ps1')

# 6. Discover the public webhook URL from the telegram preview, then wire Telegram
Write-Host "`n▶ Discovering public webhook URL..."
$pv = (& $bl get sandbox $cfg['BLAXEL_SANDBOX_NAME'] preview $cfg['BLAXEL_TELEGRAM_PREVIEW'] -o yaml 2>&1 | Out-String)
$url = ([regex]::Match($pv, 'url:\s*(\S+)')).Groups[1].Value
if (-not $url) { throw "Could not read telegram preview URL." }
$cfg['TELEGRAM_WEBHOOK_URL'] = "$url/telegram"
Save-Env
Write-Host "  webhook URL = $($cfg['TELEGRAM_WEBHOOK_URL'])"
Write-Host "▶ Re-injecting so the gateway registers the webhook (skip-build, fast)..."
& (Join-Path $PSScriptRoot 'deploy.ps1') -SkipBuild

# 7. Summary
$me = try { (Invoke-RestMethod "https://api.telegram.org/bot$tgTok/getMe").result.username } catch { '(your bot)' }
Write-Host "`n=== ✅ Done ===" -ForegroundColor Green
Write-Host "Telegram bot : @$me  - text it (only your id $tgId is allowed)"
if ($dashUser) {
  $dv = (& $bl get sandbox $cfg['BLAXEL_SANDBOX_NAME'] preview $cfg['BLAXEL_DASHBOARD_PREVIEW'] -o yaml 2>&1 | Out-String)
  $durl = ([regex]::Match($dv, 'url:\s*(\S+)')).Groups[1].Value
  Write-Host "Dashboard    : $durl   login: $dashUser / $dashPass  (saved in .env)"
}
if (-not $prov) {
  Write-Host "`n⚠ No model provider set yet - configure one before the bot can reply:" -ForegroundColor Yellow
  Write-Host "   • open the dashboard above → API keys / model, OR"
  Write-Host "   • & `"$bl`" connect sandbox $sbxName   → then run:  hermes setup model"
}
if ($mode -eq 'scale-to-zero') { Write-Host "First message after idle takes ~1 min to wake the box." }
Write-Host ""
