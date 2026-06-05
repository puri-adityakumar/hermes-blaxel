#!/usr/bin/env bash
# Back up Hermes runtime data (/root/.hermes) from the sandbox to a local file. Mirrors
# backup-data.ps1. Run BEFORE a full rebuild (free tier wipes the overlay); restore after.
#   ./scripts/backup-data.sh
set -uo pipefail
# Git Bash: stop MSYS rewriting `/process` (a bl API path, not a file path) into a Windows
# path when calling native bl.exe. Ignored on macOS/Linux.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
BL="$(command -v bl || true)"; [ -z "$BL" ] && { echo "bl not found on PATH"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$(grep -E '^BLAXEL_SANDBOX_NAME=' "$ROOT/.env" 2>/dev/null | head -n1 | cut -d= -f2-)"; SBX="${SBX:-hermes-box}"
OUTDIR="$ROOT/backups"; mkdir -p "$OUTDIR"
OUT="$OUTDIR/hermes-data-$(date +%Y%m%d-%H%M%S).tar.gz"

# Tar the durable data inside the (Linux) box and base64 it (single line via -w0).
INNER='cd /root/.hermes 2>/dev/null && tar czf - sessions memories cron state.db state.db-wal state.db-shm kanban.db SOUL.md 2>/dev/null | base64 -w0'
B64CMD="$(printf '%s' "$INNER" | base64 | tr -d '\n')"
PAYLOAD="$(printf '{"command":"echo %s | base64 -d | bash","waitForCompletion":true}' "$B64CMD")"

echo "Backing up /root/.hermes from '$SBX'..."
RESP="$("$BL" run sandbox "$SBX" --path /process --data "$PAYLOAD" 2>&1)"
# The base64 payload contains no double-quotes, so a plain extraction of the JSON
# "stdout" field is safe.
# Process API returns command output in "logs" (sometimes "stdout"), pretty-printed with a
# space after the colon. Grab the first non-empty of the two.
DATA="$(printf '%s' "$RESP" | grep -oE '"(stdout|logs)": *"[^"]+"' | head -n1 | sed -E 's/^"(stdout|logs)": *"//; s/"$//')"
[ -z "$DATA" ] && { echo "No data returned. Raw:"; echo "$RESP" | head -c 800; exit 1; }
printf '%s' "$DATA" | openssl base64 -d -A > "$OUT"
echo "✓ Saved $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
echo "  Restore later with: ./scripts/restore-data.sh \"$OUT\""
