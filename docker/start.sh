#!/usr/bin/env bash
# Launch the API and the web app together in the single manager container.
set -euo pipefail

echo "[ark-manager] applying database migrations..."
( cd apps/api && pnpm prisma migrate deploy )

echo "[ark-manager] starting API on :${API_PORT:-8787} and web on :${WEB_PORT:-3000}"

# Handle SIGTERM by forwarding it to our background children. Without this,
# bash (as PID 1) swallows the signal and the processes are SIGKILLed after
# 10s, skipping their graceful shutdown hooks.
_term() {
  echo "[ark-manager] caught SIGTERM; signaling API ($API_PID) and Web ($WEB_PID)..."
  kill -TERM "$API_PID" 2>/dev/null
  kill -TERM "$WEB_PID" 2>/dev/null
}
trap _term SIGTERM

( cd apps/api && exec node dist/apps/api/src/main.js ) &
API_PID=$!
( cd apps/web && exec pnpm start -p "${WEB_PORT:-3000}" ) &
WEB_PID=$!

# wait -n exits when the first child dies. If bash receives a trapped signal
# during wait, it executes the trap and wait returns >128. We loop so that
# we only truly exit if a child died OR we caught TERM.
while kill -0 "$API_PID" 2>/dev/null && kill -0 "$WEB_PID" 2>/dev/null; do
  wait -n "$API_PID" "$WEB_PID" || true
done

# Give children a moment to finish their own shutdown hooks before the script
# itself exits (which would end the container).
echo "[ark-manager] waiting for child processes to exit..."
wait "$API_PID" "$WEB_PID" 2>/dev/null || true
echo "[ark-manager] shutdown complete."
