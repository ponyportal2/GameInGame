#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
PI_BIN="${GAMESMITH_PI_BIN:-$(command -v pi || true)}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Set GODOT_BIN to Godot 4.7.2." >&2
  exit 2
fi
if [[ -z "$PI_BIN" || ! -x "$PI_BIN" ]]; then
  echo "Pi integration verification requires a globally installed pi executable." >&2
  exit 2
fi
TMP="${GAMESMITH_TEST_TMP:-$(mktemp -d)}"
PORT="${GAMESMITH_PI_FAKE_PORT:-31339}"
LOG="$TMP/pi-fake-requests.jsonl"
READY="$TMP/pi-fake-ready.txt"
mkdir -p "$TMP/home"
: > "$LOG"

GAMESMITH_PI_FAKE_PORT="$PORT" \
GAMESMITH_PI_FAKE_LOG="$LOG" \
GAMESMITH_PI_FAKE_KEY="pi-test-key" \
node "$ROOT/tools/fake-openai-endpoint/pi-server.mjs" >"$READY" 2>"$TMP/pi-fake-server.err" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 100); do
  if grep -q '^READY ' "$READY" 2>/dev/null; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$TMP/pi-fake-server.err" >&2
    exit 1
  fi
  sleep 0.05
done
grep -q '^READY ' "$READY"

HOME="$TMP/home" \
GAMESMITH_PI_BIN="$PI_BIN" \
GAMESMITH_PI_FAKE_URL="http://127.0.0.1:$PORT/v1" \
GAMESMITH_PI_FAKE_LOG="$LOG" \
GAMESMITH_PI_TEST_PART="${GAMESMITH_PI_TEST_PART:-}" \
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/pi_integration_runner.gd
