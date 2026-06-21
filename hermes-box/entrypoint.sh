#!/bin/bash
# Runs as PID 1 on cold boot AND keeps running across Blaxel suspend/resume.
# Starts + supervises the Hermes webhook gateway (:9099) and, optionally, the web
# dashboard (:9119). Key lessons baked in:
#  - Webhook/dashboard ports must be edge-routable → both are launched THROUGH the
#    sandbox process API (curl localhost:8080/process), never directly.
#  - Processes launched via the process API are killed by its default 600s timeout
#    (we pass timeout:0 to disable that). PID 1 (this script) survives, so the
#    (this script) survives both, so the supervision loop relaunches whatever died.
#  - The lock dir is tmpfs but is restored from the RAM snapshot on resume, so a
#    stale lock can persist → start_gateway() clears it before every (re)launch.
#  - The DASHBOARD is OPTIONAL and reusable: it only runs if a session token secret
#    is provided (HERMES_DASHBOARD_SESSION_TOKEN). Deploy without it → no dashboard.
export HERMES_HOME=/root/.hermes
export PATH="/root/.local/bin:/usr/local/bin:$PATH"
export HERMES_ACCEPT_HOOKS=1
export HERMES_GATEWAY_LOCK_DIR=/dev/shm/hglock
DASH_PORT="${HERMES_DASHBOARD_PORT:-9119}"
# Deployment mode: always-on only. (Scale-to-zero was removed - see CLAUDE.md and
# GH issue: an outbound platform like Discord can't wake a suspended box, since Blaxel
# standby resumes only on an INCOMING edge connection. Telegram's webhook could, but the
# multi-channel gateway needs the box awake to hold its outbound sockets.)
KEEPALIVE=true
mkdir -p /root/.hermes/logs /dev/shm/hglock
rm -f /root/.hermes/gateway.lock 2>/dev/null || true

# Materialize secrets (injected via `bl deploy -s`) into Hermes' .env.
{
  [ -n "$TELEGRAM_BOT_TOKEN" ]      && echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
  [ -n "$TELEGRAM_WEBHOOK_URL" ]    && echo "TELEGRAM_WEBHOOK_URL=$TELEGRAM_WEBHOOK_URL"
  [ -n "$TELEGRAM_WEBHOOK_SECRET" ] && echo "TELEGRAM_WEBHOOK_SECRET=$TELEGRAM_WEBHOOK_SECRET"
  echo "TELEGRAM_WEBHOOK_PORT=${TELEGRAM_WEBHOOK_PORT:-9099}"
  [ -n "$TELEGRAM_ALLOWED_USERS" ]  && echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS"
  # Home channel = chat where Hermes sends proactive/cron messages. Setting it here
  # (read by gateway/config.py as TELEGRAM_HOME_CHANNEL) makes it permanent and survives
  # redeploys, so the "No home channel set" prompt never appears. Value = the chat id.
  [ -n "$TELEGRAM_HOME_CHANNEL" ]    && echo "TELEGRAM_HOME_CHANNEL=$TELEGRAM_HOME_CHANNEL"
  # Web dashboard session token (read by Hermes as HERMES_DASHBOARD_SESSION_TOKEN).
  # Its PRESENCE also acts as the on/off switch for the dashboard (see below).
  [ -n "$HERMES_DASHBOARD_SESSION_TOKEN" ] && echo "HERMES_DASHBOARD_SESSION_TOKEN=$HERMES_DASHBOARD_SESSION_TOKEN"
  # Dashboard username/password login (Hermes dashboard_auth/basic plugin). When the
  # username is set, the entrypoint runs the dashboard WITHOUT --insecure so the login
  # gate engages (see below); the preview can then be public and the password is the lock.
  [ -n "$HERMES_DASHBOARD_BASIC_AUTH_USERNAME" ] && echo "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$HERMES_DASHBOARD_BASIC_AUTH_USERNAME"
  [ -n "$HERMES_DASHBOARD_BASIC_AUTH_PASSWORD" ] && echo "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
  [ -n "$HERMES_DASHBOARD_BASIC_AUTH_SECRET" ]   && echo "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$HERMES_DASHBOARD_BASIC_AUTH_SECRET"
  echo "HERMES_GATEWAY_LOCK_DIR=/dev/shm/hglock"
} > /root/.hermes/.env

# Provider-agnostic: pass through ANY model-provider credentials that were injected
# (ZAI_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, *_BASE_URL,
# *_AUTH_TOKEN, …). The wizard/.env sets whichever your chosen provider needs - we don't
# hardcode Z.AI. (TELEGRAM_* / HERMES_DASHBOARD_* don't match this pattern, so no dupes.)
env | grep -E '^[A-Z][A-Z0-9_]*_(API_KEY|BASE_URL|AUTH_TOKEN)=' >> /root/.hermes/.env
chmod 600 /root/.hermes/.env

# Write config.yaml's model section from the generic MODEL_* vars (any provider). On a
# fresh box this is what the gateway uses (it beats the auth.json probe cache - lesson #8).
# If MODEL_PROVIDER is unset the image's baked default stays and you pick a provider via
# the dashboard or `hermes setup model` (the "bring-your-own" path).
if [ -n "$MODEL_PROVIDER" ]; then
  { echo "model:"
    echo "  provider: $MODEL_PROVIDER"
    [ -n "$MODEL_NAME" ]     && echo "  default: $MODEL_NAME"
    [ -n "$MODEL_BASE_URL" ] && echo "  base_url: $MODEL_BASE_URL"
  } > /root/.hermes/config.yaml
fi

# Start the Blaxel sandbox API (manages the box on :8080) and wait for it.
/usr/local/bin/sandbox-api &
for i in $(seq 1 60); do nc -z 127.0.0.1 8080 2>/dev/null && break; sleep 1; done

# --- launchers (via the process API so the ports are edge-routable) -----------
# Unique process name per launch avoids sandbox-api name clashes with the previous
# (killed) record; edge routing is by port, not name.

GW_CMD='export HERMES_HOME=/root/.hermes PATH=/root/.local/bin:/usr/local/bin:$PATH HERMES_ACCEPT_HOOKS=1 HERMES_GATEWAY_LOCK_DIR=/dev/shm/hglock; hermes gateway run'

start_gateway() {
  rm -f /root/.hermes/gateway.lock 2>/dev/null || true
  rm -rf /dev/shm/hglock 2>/dev/null || true
  mkdir -p /dev/shm/hglock
  local b64; b64=$(printf '%s' "$GW_CMD" | base64 -w0)
  curl -s -X POST http://localhost:8080/process \
    -H "Content-Type: application/json" \
    -d "{\"command\":\"echo $b64 | base64 -d | bash\",\"name\":\"gateway-$(date +%s)\",\"keepAlive\":$KEEPALIVE,\"timeout\":0,\"waitForCompletion\":false}" \
    >> /root/.hermes/logs/gw-boot.log 2>&1
  echo "[$(date -u +%FT%TZ)] start_gateway issued" >> /root/.hermes/logs/gw-boot.log
}

# Dashboard launch. Sources .env so the dashboard sees its tokens/creds. --tui enables
# the in-browser chat; --skip-build serves the dist baked into the image.
#  - If a basic-auth USERNAME is set → run WITHOUT --insecure so the username/password
#    login gate engages (preview can be public; the password is the lock).
#  - Otherwise → keep --insecure (binds 0.0.0.0, no gate) and rely on a PRIVATE preview
#    token for access. This keeps the repo reusable either way.
DASH_INSECURE="--insecure"
[ -n "$HERMES_DASHBOARD_BASIC_AUTH_USERNAME" ] && DASH_INSECURE=""
DASH_CMD="export HERMES_HOME=/root/.hermes PATH=/root/.local/bin:/usr/local/bin:\$PATH HERMES_ACCEPT_HOOKS=1; set -a; . /root/.hermes/.env 2>/dev/null; set +a; hermes dashboard --skip-build --no-open --host 0.0.0.0 --port ${DASH_PORT} ${DASH_INSECURE} --tui"

start_dashboard() {
  local b64; b64=$(printf '%s' "$DASH_CMD" | base64 -w0)
  curl -s -X POST http://localhost:8080/process \
    -H "Content-Type: application/json" \
    -d "{\"command\":\"echo $b64 | base64 -d | bash\",\"name\":\"dashboard-$(date +%s)\",\"keepAlive\":$KEEPALIVE,\"timeout\":0,\"waitForCompletion\":false}" \
    >> /root/.hermes/logs/gw-boot.log 2>&1
  echo "[$(date -u +%FT%TZ)] start_dashboard issued (:${DASH_PORT})" >> /root/.hermes/logs/gw-boot.log
}

# Channel-agnostic liveness: is a `hermes gateway run` process alive? Telegram
# binds :9099 (older revs probed that port), but Discord is OUTBOUND-only and
# binds no port - so a :9099 probe would respawn Discord gateways forever.
gateway_alive() {
  local c
  for f in /proc/[0-9]*/cmdline; do
    c=$(tr '\0' ' ' < "$f" 2>/dev/null) || continue
    case "$c" in *"hermes gateway run"*) return 0 ;; esac
  done
  return 1
}

# Initial launch on cold boot.
start_gateway
[ -n "$HERMES_DASHBOARD_SESSION_TOKEN" ] && start_dashboard

# Supervise forever. PID 1 survives resume/crash, so this loop brings services back
# after any crash. The gateway check is process-based (gateway_alive, above) so it works
# for both Telegram (inbound :9099) and Discord (outbound, no port). The dashboard check
# stays a port probe since the dashboard always binds :9119.
while true; do
  sleep 5
  if ! gateway_alive; then
    sleep 2
    if ! gateway_alive; then
      echo "[$(date -u +%FT%TZ)] gateway not running - relaunching" >> /root/.hermes/logs/gw-boot.log
      start_gateway; sleep 12
    fi
  fi
  if [ -n "$HERMES_DASHBOARD_SESSION_TOKEN" ] && ! nc -z 127.0.0.1 "$DASH_PORT" 2>/dev/null; then
    sleep 2
    if ! nc -z 127.0.0.1 "$DASH_PORT" 2>/dev/null; then
      echo "[$(date -u +%FT%TZ)] :${DASH_PORT} unbound - relaunching dashboard" >> /root/.hermes/logs/gw-boot.log
      start_dashboard; sleep 12
    fi
  fi
done
