#!/usr/bin/env bash
# Best-effort demo — not runtime-verified by author.
#
# Spins up wol_server.py locally with a harmless demo config and exercises the
# real HTTP API (/health, /targets, POST /wake). No special hardware needed:
# the demo config broadcasts to the loopback subnet (127.255.255.255) and uses
# a placeholder MAC, so no real machine is woken.
#
# Requires: python3 (3.11+), curl. Run from the repo root:
#   ./examples/demo.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO_DIR/examples/config.demo.json"
PORT="${PORT:-18080}"

# pick python3 if present, otherwise python (must be CPython 3.11+)
PYTHON="$(command -v python3 || command -v python || true)"
if [[ -z "$PYTHON" ]]; then
    echo "error: need python3 (3.11+) on PATH" >&2
    exit 1
fi

echo "==> starting wol-pi on 127.0.0.1:$PORT (demo config: $CONFIG)"
WOL_CONFIG="$CONFIG" WOL_WEB_DIR="$REPO_DIR/web" \
    "$PYTHON" "$REPO_DIR/wol_server.py" --host 127.0.0.1 --port "$PORT" &
SRV_PID=$!
trap 'kill "$SRV_PID" 2>/dev/null || true' EXIT

# wait for the server to accept connections
for _ in $(seq 1 25); do
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

echo
echo "==> GET /health"
curl -s "http://127.0.0.1:$PORT/health"; echo

echo
echo "==> GET /targets"
curl -s "http://127.0.0.1:$PORT/targets"; echo

echo
echo "==> POST /wake  (explicit target)"
curl -s -X POST "http://127.0.0.1:$PORT/wake" \
    -H 'Content-Type: application/json' \
    -d '{"target":"desktop-pc"}'; echo

echo
echo "==> POST /wake  (no body — first target is used)"
curl -s -X POST "http://127.0.0.1:$PORT/wake"; echo

echo
echo "==> POST /wake  (unknown target -> 404)"
curl -s -X POST "http://127.0.0.1:$PORT/wake" \
    -H 'Content-Type: application/json' \
    -d '{"target":"does-not-exist"}'; echo

echo
echo "==> done. (the server logged 'sent magic packet ...' for each /wake above)"
