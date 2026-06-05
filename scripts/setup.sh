#!/usr/bin/env bash
# Hermes-on-Blaxel setup wizard (Mac/Linux). Mirrors setup.ps1.
# Clone, run this, answer a few prompts, get a live Telegram bot (+ optional dashboard).
set -uo pipefail
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPTDIR/.." && pwd)"
ENVF="$ROOT/.env"
BL="$(command -v bl || true)"

# Colors (ANSI); disabled when output is not a terminal.
if [ -t 2 ]; then
  C=$'\033[36m'; B=$'\033[1m'; D=$'\033[2m'; Y=$'\033[33m'; G=$'\033[32m'; R=$'\033[0m'
  GREEN=$'\033[38;5;28m'; ORANGE=$'\033[38;5;208m'
else C=''; B=''; D=''; Y=''; G=''; R=''; GREEN=''; ORANGE=''; fi

hex()  { openssl rand -hex "$1"; }
rule() { printf '=%.0s' $(seq 1 "$1"); }

banner() {
  local H=(
' _   _ _____ ____  __  __ _____ ____'
'| | | | ____|  _ \|  \/  | ____/ ___|'
'| |_| |  _| | |_) | |\/| |  _| \___ \'
'|  _  | |___|  _ <| |  | | |___ ___) |'
'|_| |_|_____|_| \_\_|  |_|_____|____/'
)
  local X=(
' ____  _        _    __  __ _____ _'
'| __ )| |      / \  \ \/ /| ____| |'
'|  _ \| |     / _ \  \  / |  _| | |'
'| |_) | |___ / ___ \ /  \ | |___| |___'
'|____/|_____/_/   \_\_/\_\|_____|_____|'
)
  local sep=('   ' '   ' ' x ' '   ' '   ') i
  printf '\n' >&2
  for i in 0 1 2 3 4; do
    printf '   %s%s%-38s%s%s%s%s%s%s%s\n' "$B" "$GREEN" "${H[$i]}" "$R" "$D" "${sep[$i]}" "$R" "$B$ORANGE" "${X[$i]}" "$R" >&2
  done
  local w=52
  printf '%s   +%s+\n'   "$C" "$(rule $w)"                                       >&2
  printf '   |%-*s|\n'   "$w" "  self-hosted AI agent  .  Telegram + web on Blaxel" >&2
  printf '   +%s+\n%s'   "$(rule $w)" "$R"                                       >&2
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
[ -z "$BL" ] && { printf '%s! Blaxel CLI not found.%s  Install: curl -fsSL https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.sh | sh\n' "$Y" "$R" >&2; exit 1; }
"$BL" workspaces 2>&1 | grep -q '\*' || { printf '%s! Not logged in.%s  Run: bl login\n' "$Y" "$R" >&2; exit 1; }
printf '%s+ Blaxel CLI ready.%s\n' "$G" "$R" >&2

# Reuse existing .env?
if [ -f "$ENVF" ]; then
  ANS="$(ask 'Found an existing .env - re-deploy with it as-is? (y/n)' '' optional)"
  case "$ANS" in y*|Y*) exec "$SCRIPTDIR/deploy.sh" ;; esac
fi

step "1/6" "Model provider"
opt 1 "Z.AI / GLM"
opt 2 "Anthropic (Claude)"
opt 3 "OpenAI"
opt 4 "Google Gemini"
opt 5 "Configure later in Hermes (dashboard / hermes setup model)"
PSEL="$(ask 'pick >' 'Not everyone uses Z.AI - pick yours, or 5 to set it up after deploy' optional)"
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

step "2/6" "Telegram"
TGTOK="$(ask 'bot token >' 'from @BotFather, like 123456:ABC...')"
TGID="$(ask 'your user id >' 'from @userinfobot - only this id can chat to the bot')"

step "3/6" "Web dashboard"
WANTDASH="$(ask 'enable it? (y/n)' 'a username/password admin UI (config, sessions, in-browser chat)' optional)"
DASHUSER=""; case "$WANTDASH" in y*|Y*) DASHUSER="$(ask 'dashboard username >' '')" ;; esac

step "4/6" "Run mode"
opt 1 "always-on      (instant replies, runs 24/7)"
opt 2 "scale-to-zero  (cheap; sleeps when idle, ~1 min wake)"
MODEANS="$(ask 'pick >' '' optional)"
case "$MODEANS" in 2) MODE=scale-to-zero ;; *) MODE=always-on ;; esac

step "5/6" "Sandbox name"
SBX="$(ask 'name [hermes-box] >' 'use a new name to run more than one (e.g. hermes-test)' optional)"; SBX="${SBX:-hermes-box}"

DASHPASS=""; [ -n "$DASHUSER" ] && DASHPASS="$(hex 8)"
{
  echo "DEPLOY_MODE=$MODE"
  echo "TELEGRAM_BOT_TOKEN=$TGTOK"
  echo "TELEGRAM_WEBHOOK_URL="
  echo "TELEGRAM_WEBHOOK_SECRET=$(hex 32)"
  echo "TELEGRAM_WEBHOOK_PORT=9099"
  echo "TELEGRAM_ALLOWED_USERS=$TGID"
  echo "TELEGRAM_HOME_CHANNEL=$TGID"
  echo "BLAXEL_SANDBOX_NAME=$SBX"
  echo "BLAXEL_TELEGRAM_PREVIEW=$SBX-tg"
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

step "6/6" "Deploy"
printf '   %sbuilding + deploying - the first build takes a few minutes...%s\n' "$D" "$R" >&2
"$SCRIPTDIR/deploy.sh"

printf '   %swiring the Telegram webhook...%s\n' "$D" "$R" >&2
PV="$("$BL" get sandbox "$SBX" preview "$SBX-tg" -o yaml 2>&1)"
URL="$(printf '%s\n' "$PV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
[ -z "$URL" ] && { printf '%s! could not read telegram preview URL%s\n' "$Y" "$R" >&2; exit 1; }
tmp="$(mktemp)"; sed "s#^TELEGRAM_WEBHOOK_URL=.*#TELEGRAM_WEBHOOK_URL=$URL/telegram#" "$ENVF" > "$tmp" && mv "$tmp" "$ENVF"
"$SCRIPTDIR/deploy.sh" --skip-build >/dev/null 2>&1

ME="$(curl -s "https://api.telegram.org/bot$TGTOK/getMe" | grep -o '"username":"[^"]*"' | head -n1 | cut -d'"' -f4)"
printf '\n%s%s  HERMES is live%s\n' "$G" "$B" "$R" >&2
printf '   %sTelegram %s : @%s   (only id %s can chat)\n' "$C" "$R" "${ME:-your_bot}" "$TGID" >&2
if [ -n "$DASHUSER" ]; then
  DV="$("$BL" get sandbox "$SBX" preview "$SBX-dash" -o yaml 2>&1)"
  DURL="$(printf '%s\n' "$DV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
  printf '   %sDashboard%s : %s\n' "$C" "$R" "$DURL" >&2
  printf '   %sLogin    %s : %s / %s   (saved in .env)\n' "$C" "$R" "$DASHUSER" "$DASHPASS" >&2
fi
[ -z "$PROV" ] && printf '   %s! no model provider set - configure via dashboard, or: bl connect sandbox %s  then  hermes setup model%s\n' "$Y" "$SBX" "$R" >&2
[ "$MODE" = scale-to-zero ] && printf '   %sfirst message after idle takes ~1 min to wake the box%s\n' "$D" "$R" >&2
printf '\n' >&2
