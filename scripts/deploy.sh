#!/usr/bin/env bash
# Deploy (or redeploy) the Hermes sandbox from .env - Mac/Linux. Mirrors deploy.ps1.
#   ./scripts/deploy.sh              # full build + deploy + rebind previews
#   ./scripts/deploy.sh --skip-build # config-only (faster; restarts container)
# ⚠ A full rebuild WIPES /root/.hermes runtime data (free tier, no volume) - run
#   scripts/backup-data.sh before and scripts/restore-data.sh after if you care about it.
set -uo pipefail

SKIP_BUILD=""
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD="--skip-build"

BL="$(command -v bl || true)"
[ -z "$BL" ] && { echo "Blaxel CLI 'bl' not on PATH. Install: curl -fsSL https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.sh | sh"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOX="$ROOT/hermes-box"
ENVF="$ROOT/.env"
[ -f "$ENVF" ] || { echo ".env not found. cp .env.example .env (or run scripts/setup.sh)"; exit 1; }

get() { grep -E "^$1=" "$ENVF" | head -n1 | cut -d= -f2- ; }

# Build -s args from every non-BLAXEL_, non-blank key.
SECRET_ARGS=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  [ "${line#*=}" = "$line" ] && continue        # no '='
  k="${line%%=*}"; v="${line#*=}"
  case "$k" in BLAXEL_*) continue ;; esac
  [ -z "$v" ] && continue
  SECRET_ARGS+=("-s" "$k=$v")
done < "$ENVF"

SANDBOX="$(get BLAXEL_SANDBOX_NAME)"; SANDBOX="${SANDBOX:-hermes-box}"

cd "$BOX"
echo "▶ Deploying $SANDBOX ($(( ${#SECRET_ARGS[@]} / 2 )) secrets)${SKIP_BUILD:+ [skip-build]}..."
"$BL" deploy --yes --name "$SANDBOX" $SKIP_BUILD "${SECRET_ARGS[@]}" || { echo "bl deploy failed"; exit 1; }

echo "▶ Waiting for DEPLOYED..."
ok=""
for _ in $(seq 1 60); do
  st="$("$BL" get sandbox "$SANDBOX" 2>&1 || true)"
  echo "$st" | grep -q DEPLOYED && { ok=1; break; }
  echo "$st" | grep -q FAILED && { echo "Build FAILED - run: bl logs sandbox $SANDBOX"; exit 1; }
  sleep 12
done
[ -n "$ok" ] || { echo "Timed out waiting for DEPLOYED"; exit 1; }

echo "▶ Re-binding previews (generated from .env for '$SANDBOX')..."
TG="$(get BLAXEL_TELEGRAM_PREVIEW)";  TG="${TG:-porttest2}"
DB="$(get BLAXEL_DASHBOARD_PREVIEW)"; DB="${DB:-dashboard}"
TGPORT="$(get TELEGRAM_WEBHOOK_PORT)"; TGPORT="${TGPORT:-9099}"
DBPFX="$(get BLAXEL_DASHBOARD_PREFIX)"; DBPFX="${DBPFX:-$DB}"
DASH_USER="$(get HERMES_DASHBOARD_BASIC_AUTH_USERNAME)"

TGF="$(mktemp)"
printf 'kind: Preview\nmetadata:\n  name: %s\n  resourceName: %s\nspec:\n  port: %s\n  public: true\n' "$TG" "$SANDBOX" "$TGPORT" > "$TGF"
"$BL" delete sandbox "$SANDBOX" preview "$TG" >/dev/null 2>&1 || true
"$BL" apply -f "$TGF" >/dev/null 2>&1 || true

if [ -n "$DASH_USER" ]; then
  DBF="$(mktemp)"
  printf 'kind: Preview\nmetadata:\n  name: %s\n  resourceName: %s\nspec:\n  port: 9119\n  public: true\n  prefixUrl: %s\n' "$DB" "$SANDBOX" "$DBPFX" > "$DBF"
  "$BL" delete sandbox "$SANDBOX" preview "$DB" >/dev/null 2>&1 || true
  "$BL" apply -f "$DBF" >/dev/null 2>&1 || true
fi
echo "✓ Deployed and re-bound. Text the bot / open the dashboard to verify."
