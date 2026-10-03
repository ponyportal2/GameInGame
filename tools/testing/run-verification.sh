#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Set GODOT_BIN to a Godot 4.7.2 executable, or pass it as the first argument." >&2
  exit 2
fi
TMP="${GAMESMITH_TEST_TMP:-$(mktemp -d)}"

python3 "$ROOT/tools/testing/verify_windows_package.py"
if command -v go >/dev/null 2>&1; then
  (cd "$ROOT/tools/windows-bootstrap" && go test ./...)
else
  echo "SKIP: Go not installed; Windows release-bootstrap unit tests not run"
fi

mkdir -p "$TMP/unit-home"
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --editor --quit >/dev/null 2>&1 || true
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/test_runner.gd
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/reliability_runner.gd
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/diagnostics_runner.gd
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/cache_regression_runner.gd
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/cache_edge_regression_runner.gd
HOME="$TMP/unit-home" "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/script_load_policy_runner.gd
node --test "$ROOT/tests/workspace-paths.test.mjs" "$ROOT/tests/model-capabilities.test.mjs" "$ROOT/tests/diagnostic-delivery.test.mjs"
if command -v xvfb-run >/dev/null 2>&1; then
  mkdir -p "$TMP/windowed-home"
  xvfb-run -a env HOME="$TMP/windowed-home" GODOT_SILENCE_ROOT_WARNING=1 \
    "$GODOT_BIN" --audio-driver Dummy --path "$ROOT" --script res://tests/windowed_input_runner.gd
else
  echo "SKIP: xvfb-run not installed; windowed input-ownership regression test not run"
fi
# Production agent acceptance is Pi-backed. The default Pi runner executes all
# phased acceptance slices in one process: normal runtime, native compaction,
# migration/deletion, and packaging/discovery.
GAMESMITH_TEST_TMP="$TMP/pi-e2e-all" GODOT_BIN="$GODOT_BIN" "$ROOT/tools/testing/run-pi-e2e.sh"

# Real process-level migration check: v1.4 and earlier used the spaced application
# name. A launch of the new project must copy that data into GameSmithHost and
# start the new global debug log without destroying the old directory.
MIG_HOME="$TMP/migration-home"
OLD_ROOT="$MIG_HOME/.local/share/godot/app_userdata/GameSmith Host"
NEW_ROOT="$MIG_HOME/.local/share/godot/app_userdata/GameSmithHost"
mkdir -p "$OLD_ROOT/games/Legacy Game" "$OLD_ROOT/host"
printf 'extends Node\n' > "$OLD_ROOT/games/Legacy Game/main.gd"
printf '{"provider":"custom"}' > "$OLD_ROOT/host/settings.json"
HOME="$MIG_HOME" "$GODOT_BIN" --headless --path "$ROOT" --quit-after 3 >/dev/null 2>&1 || true
test -f "$NEW_ROOT/games/Legacy Game/main.gd"
test -f "$NEW_ROOT/host/settings.json"
test -f "$NEW_ROOT/logs/gamesmith-app.log"
test -f "$OLD_ROOT/games/Legacy Game/main.gd"
echo "PASS: legacy GameSmith Host data migrates to GameSmithHost without deleting the old data"

echo "PASS: GameSmith source verification complete"
