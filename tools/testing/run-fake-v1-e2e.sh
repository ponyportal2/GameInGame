#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Set GODOT_BIN to a Godot 4.7.2 executable, or pass it as the first argument." >&2
  exit 2
fi
PORT="${GAMESMITH_FAKE_PORT:-3017}"
TMP="${GAMESMITH_TEST_TMP:-$(mktemp -d)}"
LOG="$TMP/fake-v1-requests.jsonl"
SERVER_LOG="$TMP/fake-v1-server.log"
mkdir -p "$TMP/http-home" "$TMP/restart-home"
PORT="$PORT" HOST=127.0.0.1 GAMESMITH_FAKE_LOG="$LOG" node "$ROOT/tools/fake-openai-endpoint/gamesmith-server.mjs" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null
BASE="http://127.0.0.1:$PORT/v1"
HOME="$TMP/http-home" "$GODOT_BIN" --headless --path "$ROOT" --editor --quit >/dev/null 2>&1 || true
HOME="$TMP/http-home" GAMESMITH_FAKE_BASE="$BASE" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/http_integration_runner.gd
HOME="$TMP/restart-home" "$GODOT_BIN" --headless --path "$ROOT" --editor --quit >/dev/null 2>&1 || true
HOME="$TMP/restart-home" GAMESMITH_FAKE_BASE="$BASE" GAMESMITH_RESTART_PHASE=seed "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/http_restart_phase.gd
HOME="$TMP/restart-home" GAMESMITH_FAKE_BASE="$BASE" GAMESMITH_RESTART_PHASE=verify "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/http_restart_phase.gd
REQS=$(wc -l < "$LOG" | tr -d ' ')
echo "PASS: fake /v1 workflow completed with $REQS real HTTP requests"
echo "Artifacts: $TMP"
