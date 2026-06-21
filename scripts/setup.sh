#!/usr/bin/env bash
# Hermes-on-Blaxel setup wizard. Mac/Linux native, or Windows via Git Bash / WSL.
# Clone, run this, answer a few prompts, get a live Telegram bot (+ optional dashboard).
set -uo pipefail
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPTDIR/.." && pwd)"
ENVF="$ROOT/.env"
BL="$(command -v bl || true)"

# Colors (ANSI); disabled when output is not a terminal.
if [ -t 2 ]; then
  C=$'\033[36m'; B=$'\033[1m'; D=$'\033[2m'; Y=$'\033[33m'; G=$'\033[32m'; R=$'\033[0m'; GREEN=$'\033[38;5;40m'; ORANGE=$'\033[38;5;208m'
else C=''; B=''; D=''; Y=''; G=''; R=''; GREEN=''; ORANGE=''; fi

hex() { openssl rand -hex "$1"; }

banner() {
  local h1=' _   _ _____ ____  __  __ _____ ____'
  local h2='| | | | ____|  _ \  \/  | ____/ ___|'
  local h3='| |_| |  _| | |_) | |\/| |  _| \___ \'
  local h4='|  _  | |___|  _ <| |  | | |___ ___) |'
  local h5='|_| |_|_____|_| \_\_|  |_|_____|____/'
  local b1=' ____  _        _    __  __ _____ _'
  local b2='| __ )| |      / \  \ \/ /| ____| |'
  local b3='|  _ \| |     / _ \  \  / |  _| | |'
  local b4='| |_) | |___ / ___ \ /  \ | |___| |___'
  local b5='|____/|_____/_/   \_\_/\_\|_____|_____|'
  printf '\n' >&2
  printf '   %s%-38s%s   %s%s%s\n' "$GREEN" "$h1" "$R" "$ORANGE" "$b1" "$R" >&2
  printf '   %s%-38s%s   %s%s%s\n' "$GREEN" "$h2" "$R" "$ORANGE" "$b2" "$R" >&2
  printf '   %s%-38s%s %sx%s %s%s%s\n' "$GREEN" "$h3" "$R" "$D" "$R" "$ORANGE" "$b3" "$R" >&2
  printf '   %s%-38s%s   %s%s%s\n' "$GREEN" "$h4" "$R" "$ORANGE" "$b4" "$R" >&2
  printf '   %s%-38s%s   %s%s%s\n' "$GREEN" "$h5" "$R" "$ORANGE" "$b5" "$R" >&2
  printf '\n' >&2
  local sub='self-hosted autonomous agent on a managed sandbox'
  local bar; bar="$(printf '%*s' "$(( ${#sub} + 3 ))" '' | tr ' ' '=')"
  printf '   %s+%s+%s\n' "$C" "$bar" "$R" >&2
  printf '   %s|%s  %s %s|%s\n' "$C" "$R" "$sub" "$C" "$R" >&2
  printf '   %s+%s+%s\n\n' "$C" "$bar" "$R" >&2
}

step() { printf '\n%s%s[%s]%s %s%s%s\n' "$B" "$C" "$1" "$R" "$B" "$2" "$R" >&2; }
opt()  { printf '     %s%s.%s %s\n' "$B$C" "$1" "$R" "$2" >&2; }

ask() {  # ask "Prompt" "help" [optional]   -> echoes the answer on stdout
  local prompt="$1" help="${2:-}" opt="${3:-}" v=""
  [ -n "$help" ] && printf '   %s%s%s\n' "$D" "$help" "$R" >&2
  while :; do
    printf '   %s%s%s ' "$C" "$prompt" "$R" >&2; read -r v; v="${v%$'\r'}"  # strip trailing CR (Git Bash / CRLF terminals)
    [ -n "$v" ] && { printf '%s' "$v"; return; }
    [ -n "$opt" ] && return
    printf '   %s(required)%s\n' "$Y" "$R" >&2
  done
}

banner

# Prerequisites
if [ -z "$BL" ]; then
  printf '%s! Blaxel CLI not found.%s\n' "$Y" "$R" >&2
  ANS="$(ask 'install it now? (y/n)' '' optional)"
  case "$ANS" in
    y*|Y*)
      printf '   %sinstalling...%s\n' "$D" "$R" >&2
      curl -fsSL https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.sh | sh || { printf '%s! install failed%s\n' "$Y" "$R" >&2; exit 1; }
      BL="$(command -v bl || true)"
      [ -z "$BL" ] && { printf '%s! installed but not on PATH - open a new shell and re-run%s\n' "$Y" "$R" >&2; exit 1; }
      ;;
    *) exit 1 ;;
  esac
fi
"$BL" workspaces 2>&1 | grep -q '\*' || { printf '%s! Not logged in.%s  Run: bl login\n' "$Y" "$R" >&2; exit 1; }
printf '%s+ Blaxel CLI ready.%s\n' "$G" "$R" >&2

# Reuse existing .env?
if [ -f "$ENVF" ]; then
  ANS="$(ask 'Found an existing .env - re-deploy with it as-is? (y/n)' '' optional)"
  case "$ANS" in y*|Y*) exec "$SCRIPTDIR/deploy.sh" ;; esac
fi

step "1/5" "Model provider"
opt 1 "Z.AI / GLM"
opt 2 "Anthropic (Claude)"
opt 3 "OpenAI"
opt 4 "Google Gemini"
opt 5 "Configure later in Hermes (dashboard / hermes setup model)"
PSEL="$(ask 'pick >' '' optional)"
PROV=""; PROVKEYVAR=""; PROVMODEL=""; PROVKEY=""; PROVBASE=""
case "$PSEL" in
  2) PROV=anthropic; PROVKEYVAR=ANTHROPIC_API_KEY; PROVMODEL=claude-sonnet-4-6 ;;
  3) PROV=openai;    PROVKEYVAR=OPENAI_API_KEY;    PROVMODEL=gpt-4o ;;
  4) PROV=gemini;    PROVKEYVAR=GEMINI_API_KEY;    PROVMODEL=gemini-2.5-pro ;;
  5) PROV="" ;;
  *) PROV=zai; PROVKEYVAR=ZAI_API_KEY; PROVMODEL=glm-5.1 ;;
esac
if [ -n "$PROV" ]; then
  PROVKEY="$(ask "$PROV API key >" 'paste your provider key')"
  M="$(ask "model name [$PROVMODEL] >" '' optional)"; [ -n "$M" ] && PROVMODEL="$M"
  if [ "$PROV" = zai ]; then CP="$(ask 'use Z.AI Coding Plan endpoint? (y/n)' '' optional)"; case "$CP" in n*|N*) : ;; *) PROVBASE='https://api.z.ai/api/coding/paas/v4' ;; esac; fi
fi

step "2/5" "Messaging platform"
opt 1 "Telegram"
opt 2 "Discord"
opt 3 "Set up later (dashboard / hermes gateway setup)"
CSEL="$(ask 'pick >' '' optional)"
CHANNEL=""; TGTOK=""; TGID=""; DTOK=""; DID=""
case "$CSEL" in
  1) CHANNEL=telegram
     TGTOK="$(ask 'bot token >' 'from @BotFather, like 123456:ABC...')"
     TGID="$(ask 'your user id >' 'from @userinfobot - only this id can chat to the bot')" ;;
  2) CHANNEL=discord
     DTOK="$(ask 'bot token >' 'from the Discord Developer Portal - Bot page')"
     DID="$(ask 'your user id >' 'Developer Mode on, right-click yourself - Copy User ID')" ;;
  *) CHANNEL="" ;;
esac

step "3/5" "Web dashboard"
WANTDASH="$(ask 'enable it? (y/n)' 'a username/password admin UI (config, sessions, in-browser chat)' optional)"
DASHUSER=""; case "$WANTDASH" in y*|Y*) DASHUSER="$(ask 'dashboard username >' '')" ;; esac

step "4/5" "Sandbox name"
SBX="$(ask 'name [hermes-box] >' 'use a new name to run more than one (e.g. hermes-test)' optional)"; SBX="${SBX:-hermes-box}"

DASHPASS=""; [ -n "$DASHUSER" ] && DASHPASS="$(hex 8)"
{
  echo "DEPLOY_MODE=always-on"
  if [ "$CHANNEL" = telegram ]; then
    echo "TELEGRAM_BOT_TOKEN=$TGTOK"
    echo "TELEGRAM_WEBHOOK_URL="
    echo "TELEGRAM_WEBHOOK_SECRET=$(hex 32)"
    echo "TELEGRAM_WEBHOOK_PORT=9099"
    echo "TELEGRAM_ALLOWED_USERS=$TGID"
    echo "TELEGRAM_HOME_CHANNEL=$TGID"
    echo "BLAXEL_TELEGRAM_PREVIEW=$SBX-tg"
  elif [ "$CHANNEL" = discord ]; then
    echo "DISCORD_BOT_TOKEN=$DTOK"
    echo "DISCORD_ALLOWED_USERS=$DID"
  fi
  echo "BLAXEL_SANDBOX_NAME=$SBX"
  echo "BLAXEL_DASHBOARD_PREVIEW=$SBX-dash"
  echo "BLAXEL_DASHBOARD_PREFIX=$SBX-dash"
  if [ -n "$PROV" ]; then
    echo "MODEL_PROVIDER=$PROV"; echo "MODEL_NAME=$PROVMODEL"
    [ -n "$PROVBASE" ] && echo "MODEL_BASE_URL=$PROVBASE"
    echo "$PROVKEYVAR=$PROVKEY"
  fi
  if [ -n "$DASHUSER" ]; then
    echo "HERMES_DASHBOARD_SESSION_TOKEN=$(hex 24)"
    echo "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$DASHUSER"
    echo "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$DASHPASS"
    echo "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(hex 32)"
  fi
} > "$ENVF"
printf '%s+ wrote .env (secrets generated)%s\n' "$G" "$R" >&2

step "5/5" "Deploy"
printf '   %sbuilding + deploying - the first build takes a few minutes...%s\n' "$D" "$R" >&2
"$SCRIPTDIR/deploy.sh"

if [ "$CHANNEL" = telegram ]; then
  printf '   %swiring the Telegram webhook...%s\n' "$D" "$R" >&2
  PV="$("$BL" get sandbox "$SBX" preview "$SBX-tg" -o yaml 2>&1)"
  URL="$(printf '%s\n' "$PV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
  [ -z "$URL" ] && { printf '%s! could not read telegram preview URL%s\n' "$Y" "$R" >&2; exit 1; }
  tmp="$(mktemp)"; sed "s#^TELEGRAM_WEBHOOK_URL=.*#TELEGRAM_WEBHOOK_URL=$URL/telegram#" "$ENVF" > "$tmp" && mv "$tmp" "$ENVF"
  "$SCRIPTDIR/deploy.sh" --skip-build >/dev/null 2>&1
fi

printf '\n%s%s  HERMES is live%s\n' "$G" "$B" "$R" >&2
case "$CHANNEL" in
  telegram)
    ME="$(curl -s "https://api.telegram.org/bot$TGTOK/getMe" | grep -o '"username":"[^"]*"' | head -n1 | cut -d'"' -f4)"
    printf '   %sTelegram %s : @%s   (only id %s can chat)\n' "$C" "$R" "${ME:-your_bot}" "$TGID" >&2 ;;
  discord)
    DME="$(curl -s -H "Authorization: Bot $DTOK" https://discord.com/api/v10/users/@me | grep -o '"username":"[^"]*"' | head -n1 | cut -d'"' -f4)"
    printf '   %sDiscord  %s : %s   (only id %s can chat - DM or @mention in a server)\n' "$C" "$R" "${DME:-your_bot}" "$DID" >&2 ;;
  *)
    printf '   %s! no messaging platform set - configure via dashboard, or: bl connect sandbox %s  then  hermes gateway setup%s\n' "$Y" "$SBX" "$R" >&2 ;;
esac
if [ -n "$DASHUSER" ]; then
  DV="$("$BL" get sandbox "$SBX" preview "$SBX-dash" -o yaml 2>&1)"
  DURL="$(printf '%s\n' "$DV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
  printf '   %sDashboard%s : %s\n' "$C" "$R" "$DURL" >&2
  printf '   %sLogin    %s : %s / %s   (saved in .env)\n' "$C" "$R" "$DASHUSER" "$DASHPASS" >&2
fi
[ -z "$PROV" ] && printf '   %s! no model provider set - configure via dashboard, or: bl connect sandbox %s  then  hermes setup model%s\n' "$Y" "$SBX" "$R" >&2
printf '\n' >&2
