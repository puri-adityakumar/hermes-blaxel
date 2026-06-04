#requires -Version 5
# Hermes-on-Blaxel setup wizard (Windows). Mirrors setup.sh.
# Clone, run this, answer a few prompts, get a live Telegram bot (+ optional dashboard).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$envF = Join-Path $root '.env'
$bl   = Join-Path $env:LOCALAPPDATA 'blaxel\bl.exe'

function Hex([int]$n) {
  $b = New-Object byte[] $n
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  -join ($b | ForEach-Object { $_.ToString('x2') })
}
function Banner {
  $e=[char]27; $grn="$e[38;5;28m"; $org="$e[38;5;208m"; $cyn="$e[36m"; $rst="$e[0m"
$art = @'
    _   _ _____ ____  __  __ _____ ____
   | | | | ____|  _ \|  \/  | ____/ ___|
   | |_| |  _| | |_) | |\/| |  _| \___ \
   |  _  | |___|  _ <| |  | | |___ ___) |
   |_| |_|_____|_| \_\_|  |_|_____|____/
'@
  Write-Host ($grn + $art + $rst)
  Write-Host ("                 x  {0}BLAXEL{1}" -f $org, $rst)
  $w = 52; $bar = '=' * $w
  Write-Host ("$cyn   +{0}+" -f $bar)
  Write-Host ("   |{0,-$w}|" -f "  self-hosted AI agent  .  Telegram + web on Blaxel")
  Write-Host ("   +{0}+$rst" -f $bar)
  Write-Host ""
}
function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Opt($n, $t)  { Write-Host "     $n. " -ForegroundColor Cyan -NoNewline; Write-Host $t }
function Ask([string]$prompt, [string]$help, [switch]$Optional) {
  if ($help) { Write-Host "   $help" -ForegroundColor DarkGray }
  while ($true) {
    $v = (Read-Host "   $prompt").Trim()
    if ($v -or $Optional) { return $v }
    Write-Host "   (required)" -ForegroundColor Yellow
  }
}

Banner

# Prerequisites
if (-not (Test-Path $bl)) {
  Write-Host "! Blaxel CLI not found. Install: irm https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.ps1 | iex" -ForegroundColor Yellow
  throw "Install bl, restart the shell, then re-run."
}
if ((& $bl workspaces 2>&1 | Out-String) -notmatch '\*') {
  Write-Host "! Not logged in. Run:  bl login" -ForegroundColor Yellow
  throw "Log in first, then re-run."
}
Write-Host "+ Blaxel CLI ready." -ForegroundColor Green

# Reuse existing .env?
if (Test-Path $envF) {
  $ans = Ask "Found an existing .env - re-deploy with it as-is? (y/n)" "" -Optional
  if ($ans -match '^y') { & (Join-Path $PSScriptRoot 'deploy.ps1'); return }
}

Step "1/6" "Model provider"
Opt 1 "Z.AI / GLM"
Opt 2 "Anthropic (Claude)"
Opt 3 "OpenAI"
Opt 4 "Google Gemini"
Opt 5 "Configure later in Hermes (dashboard / hermes setup model)"
$pSel = Ask "pick >" "Not everyone uses Z.AI - pick yours, or 5 to set it up after deploy" -Optional
$prov=''; $provKeyVar=''; $provKey=''; $provModel=''; $provBase=''
switch ($pSel) {
  '2' { $prov='anthropic'; $provKeyVar='ANTHROPIC_API_KEY'; $provModel='claude-sonnet-4-6' }
  '3' { $prov='openai';    $provKeyVar='OPENAI_API_KEY';    $provModel='gpt-4o' }
  '4' { $prov='gemini';    $provKeyVar='GEMINI_API_KEY';    $provModel='gemini-2.5-pro' }
  '5' { $prov='' }
  default { $prov='zai'; $provKeyVar='ZAI_API_KEY'; $provModel='glm-5.1' }
}
if ($prov) {
  $provKey = Ask "$prov API key >" "paste your provider key"
  $m = Ask "model name [$provModel] >" "" -Optional; if ($m) { $provModel = $m }
  if ($prov -eq 'zai') { $cp = Ask "use Z.AI Coding Plan endpoint? (y/n)" "" -Optional; if ($cp -notmatch '^n') { $provBase='https://api.z.ai/api/coding/paas/v4' } }
}

Step "2/6" "Telegram"
$tgTok = Ask "bot token >" "from @BotFather, like 123456:ABC..."
$tgId  = Ask "your user id >" "from @userinfobot - only this id can chat to the bot"

Step "3/6" "Web dashboard"
$wantDash = Ask "enable it? (y/n)" "a username/password admin UI (config, sessions, in-browser chat)" -Optional
$dashUser = ''
if ($wantDash -match '^y') { $dashUser = Ask "dashboard username >" "" }

Step "4/6" "Run mode"
Opt 1 "always-on      (instant replies, runs 24/7)"
Opt 2 "scale-to-zero  (cheap; sleeps when idle, ~1 min wake)"
$modeAns = Ask "pick >" "" -Optional
$mode = if ($modeAns -eq '2') { 'scale-to-zero' } else { 'always-on' }

Step "5/6" "Sandbox name"
$sbxName = Ask "name [hermes-box] >" "use a new name to run more than one (e.g. hermes-test)" -Optional
if (-not $sbxName) { $sbxName = 'hermes-box' }

# Generate secrets + write .env
$cfg = [ordered]@{
  DEPLOY_MODE              = $mode
  TELEGRAM_BOT_TOKEN       = $tgTok
  TELEGRAM_WEBHOOK_URL     = ''
  TELEGRAM_WEBHOOK_SECRET  = (Hex 32)
  TELEGRAM_WEBHOOK_PORT    = '9099'
  TELEGRAM_ALLOWED_USERS   = $tgId
  TELEGRAM_HOME_CHANNEL    = $tgId
  BLAXEL_SANDBOX_NAME      = $sbxName
  BLAXEL_TELEGRAM_PREVIEW  = "$sbxName-tg"
  BLAXEL_DASHBOARD_PREVIEW = "$sbxName-dash"
  BLAXEL_DASHBOARD_PREFIX  = "$sbxName-dash"
}
if ($prov) {
  $cfg['MODEL_PROVIDER'] = $prov; $cfg['MODEL_NAME'] = $provModel
  if ($provBase) { $cfg['MODEL_BASE_URL'] = $provBase }
  $cfg[$provKeyVar] = $provKey
}
$dashPass = ''
if ($dashUser) {
  $dashPass = (Hex 8)
  $cfg['HERMES_DASHBOARD_SESSION_TOKEN']       = (Hex 24)
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_USERNAME'] = $dashUser
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_PASSWORD'] = $dashPass
  $cfg['HERMES_DASHBOARD_BASIC_AUTH_SECRET']   = (Hex 32)
}
function Save-Env { ($cfg.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Path $envF -Encoding ascii }
Save-Env
Write-Host "+ wrote .env (secrets generated)" -ForegroundColor Green

Step "6/6" "Deploy"
Write-Host "   building + deploying - the first build takes a few minutes..." -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot 'deploy.ps1')

Write-Host "   wiring the Telegram webhook..." -ForegroundColor DarkGray
$pv = (& $bl get sandbox $sbxName preview "$sbxName-tg" -o yaml 2>&1 | Out-String)
$url = ([regex]::Match($pv, 'url:\s*(\S+)')).Groups[1].Value
if (-not $url) { throw "Could not read telegram preview URL." }
$cfg['TELEGRAM_WEBHOOK_URL'] = "$url/telegram"; Save-Env
& (Join-Path $PSScriptRoot 'deploy.ps1') -SkipBuild | Out-Null

$me = try { (Invoke-RestMethod "https://api.telegram.org/bot$tgTok/getMe").result.username } catch { 'your_bot' }
Write-Host "`n  HERMES is live" -ForegroundColor Green
Write-Host "   Telegram  : " -ForegroundColor Cyan -NoNewline; Write-Host "@$me   (only id $tgId can chat)"
if ($dashUser) {
  $dv = (& $bl get sandbox $sbxName preview "$sbxName-dash" -o yaml 2>&1 | Out-String)
  $durl = ([regex]::Match($dv, 'url:\s*(\S+)')).Groups[1].Value
  Write-Host "   Dashboard : " -ForegroundColor Cyan -NoNewline; Write-Host $durl
  Write-Host "   Login     : " -ForegroundColor Cyan -NoNewline; Write-Host "$dashUser / $dashPass   (saved in .env)"
}
if (-not $prov) { Write-Host "   ! no model provider set - configure via dashboard, or: bl connect sandbox $sbxName then hermes setup model" -ForegroundColor Yellow }
if ($mode -eq 'scale-to-zero') { Write-Host "   first message after idle takes ~1 min to wake the box" -ForegroundColor DarkGray }
Write-Host ""
