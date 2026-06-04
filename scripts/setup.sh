#!/usr/bin/env bash
# Hermes-on-Blaxel setup wizard - Mac/Linux. Mirrors setup.ps1.
# Clone → ./scripts/setup.sh → answer a few prompts → live Telegram bot (+ optional dashboard).
set -uo pipefail

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPTDIR/.." && pwd)"
ENVF="$ROOT/.env"
BL="$(command -v bl || true)"

hex() { openssl rand -hex "$1"; }
ask() {  # ask "Prompt" "help" [optional]   -> echoes the answer
  local prompt="$1" help="${2:-}" opt="${3:-}" v=""
  [ -n "$help" ] && printf '  %s\n' "$help" >&2
  while :; do
    printf '%s: ' "$prompt" >&2; read -r v
    [ -n "$v" ] && { printf '%s' "$v"; return; }
    [ -n "$opt" ] && return
    printf '  (required)\n' >&2
  done
}

printf '\n=== Hermes-on-Blaxel setup ===\n\n'

# 1. Prerequisites
[ -z "$BL" ] && { echo "Blaxel CLI 'bl' not found. Install: curl -fsSL https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.sh | sh"; exit 1; }
"$BL" workspaces 2>&1 | grep -q '\*' || { echo "Not logged in. Run: bl login"; exit 1; }
echo "✓ Blaxel CLI ready."

# 2. Reuse existing .env?
if [ -f "$ENVF" ]; then
  ANS="$(ask 'Found an existing .env. Re-deploy with it as-is? (y/n)' '' optional)"
  case "$ANS" in y*|Y*) exec "$SCRIPTDIR/deploy.sh" ;; esac
  echo "Re-running the wizard (will overwrite .env)..."
fi

# 3. Inputs
printf 'Model provider  [1] Z.AI/GLM  [2] Anthropic  [3] OpenAI  [4] Gemini  [5] configure later in Hermes\n' >&2
PSEL="$(ask 'Pick a provider (1-5)' 'Not everyone uses Z.AI - or 5 to set it up in the dashboard / hermes setup model after deploy' optional)"
PROV=""; PROVKEYVAR=""; PROVMODEL=""; PROVKEY=""; PROVBASE=""
case "$PSEL" in
  2) PROV=anthropic; PROVKEYVAR=ANTHROPIC_API_KEY; PROVMODEL=claude-sonnet-4-6 ;;
  3) PROV=openai;    PROVKEYVAR=OPENAI_API_KEY;    PROVMODEL=gpt-4o ;;
  4) PROV=gemini;    PROVKEYVAR=GEMINI_API_KEY;    PROVMODEL=gemini-2.5-pro ;;
  5) PROV="" ;;
  *) PROV=zai; PROVKEYVAR=ZAI_API_KEY; PROVMODEL=glm-5.1 ;;
esac
if [ -n "$PROV" ]; then
  PROVKEY="$(ask "$PROV API key" 'Paste your provider key')"
  M="$(ask "Model name [$PROVMODEL]" '' optional)"; [ -n "$M" ] && PROVMODEL="$M"
  if [ "$PROV" = zai ]; then CP="$(ask 'Use Z.AI Coding Plan endpoint? (y/n)' '' optional)"; case "$CP" in n*|N*) : ;; *) PROVBASE='https://api.z.ai/api/coding/paas/v4' ;; esac; fi
fi
TGTOK="$(ask 'Telegram bot token' 'From @BotFather (123456:ABC...)')"
TGID="$(ask 'Your Telegram user id' 'From @userinfobot - only this user can chat')"
WANTDASH="$(ask 'Enable the web dashboard? (y/n)' 'Adds a username/password admin UI' optional)"
DASHUSER=""; case "$WANTDASH" in y*|Y*) DASHUSER="$(ask '  Dashboard username' '')" ;; esac
MODEANS="$(ask 'Run mode: [1] always-on (instant, 24/7)  [2] scale-to-zero (cheap, ~1 min wake)' '' optional)"
case "$MODEANS" in 2) MODE=scale-to-zero ;; *) MODE=always-on ;; esac
SBX="$(ask 'Sandbox name [hermes-box]' 'Lets you run more than one (e.g. hermes-test)' optional)"; SBX="${SBX:-hermes-box}"

# 4. Generate secrets + write .env
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
echo "✓ Wrote .env (secrets generated)."

# 5. First deploy
"$SCRIPTDIR/deploy.sh"

# 6. Discover webhook URL → wire Telegram → fast redeploy
echo "▶ Discovering public webhook URL..."
PV="$("$BL" get sandbox "$SBX" preview "$SBX-tg" -o yaml 2>&1)"
URL="$(printf '%s\n' "$PV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
[ -z "$URL" ] && { echo "Could not read telegram preview URL"; exit 1; }
tmp="$(mktemp)"; sed "s#^TELEGRAM_WEBHOOK_URL=.*#TELEGRAM_WEBHOOK_URL=$URL/telegram#" "$ENVF" > "$tmp" && mv "$tmp" "$ENVF"
echo "  webhook URL = $URL/telegram"
echo "▶ Re-injecting so the gateway registers the webhook (skip-build)..."
"$SCRIPTDIR/deploy.sh" --skip-build

# 7. Summary
ME="$(curl -s "https://api.telegram.org/bot$TGTOK/getMe" | grep -o '"username":"[^"]*"' | head -n1 | cut -d'"' -f4)"
printf '\n=== ✅ Done ===\n'
echo "Telegram bot : @${ME:-your_bot}  - text it (only id $TGID allowed)"
if [ -n "$DASHUSER" ]; then
  DV="$("$BL" get sandbox "$SBX" preview "$SBX-dash" -o yaml 2>&1)"
  DURL="$(printf '%s\n' "$DV" | grep -E '^[[:space:]]*url:' | head -n1 | sed -E 's/.*url:[[:space:]]*//')"
  echo "Dashboard    : $DURL   login: $DASHUSER / $DASHPASS  (saved in .env)"
fi
[ -z "$PROV" ] && { echo "⚠ No model provider set - configure one before the bot can reply:"; echo "   • dashboard → API keys / model, OR"; echo "   • bl connect sandbox $SBX  → then: hermes setup model"; }
[ "$MODE" = scale-to-zero ] && echo "First message after idle takes ~1 min to wake the box."
echo
