#!/usr/bin/env bash
# Restore Hermes runtime data into the sandbox from a local backup. Mirrors restore-data.ps1.
# Uploads the archive in ≤90 KB base64 chunks (avoids CLI/arg length limits) via bl run --file.
#   ./scripts/restore-data.sh ./backups/hermes-data-YYYYMMDD-HHMMSS.tar.gz
set -uo pipefail
INFILE="${1:-}"
[ -z "$INFILE" ] && { echo "usage: ./scripts/restore-data.sh <backup.tar.gz>"; exit 1; }
[ -f "$INFILE" ] || { echo "backup not found: $INFILE"; exit 1; }
BL="$(command -v bl || true)"; [ -z "$BL" ] && { echo "bl not found on PATH"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$(grep -E '^BLAXEL_SANDBOX_NAME=' "$ROOT/.env" 2>/dev/null | head -n1 | cut -d= -f2-)"; SBX="${SBX:-hermes-box}"

runbox() {  # runbox "<shell command>"  - command must contain no double-quotes/backslashes
  local cmd="$1" pf; pf="$(mktemp)"
  printf '{"command":"%s","waitForCompletion":true}' "$cmd" > "$pf"
  "$BL" run sandbox "$SBX" --path /process --file "$pf" >/dev/null 2>&1 || true
  rm -f "$pf"
}

B64="$(openssl base64 -A -in "$INFILE")"   # single-line base64
LEN=${#B64}; CHUNK=90000
echo "Restoring $INFILE (${LEN} b64 chars) into '$SBX':/root/.hermes ..."
runbox ': > /tmp/r.b64'                      # truncate staging file
i=0; n=0
while [ "$i" -lt "$LEN" ]; do
  part="${B64:$i:$CHUNK}"
  runbox "printf '%s' '$part' >> /tmp/r.b64"
  i=$((i + CHUNK)); n=$((n + 1)); echo "  chunk $n"
done
runbox 'base64 -d /tmp/r.b64 > /tmp/restore.tar.gz && tar xzf /tmp/restore.tar.gz -C /root/.hermes && echo RESTORED_OK'
echo "✓ Restored into /root/.hermes"
