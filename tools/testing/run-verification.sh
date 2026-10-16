#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" ]]; then echo "Set GODOT_BIN or pass it as the first argument." >&2; exit 2; fi
exec node "$ROOT/tools/testing/verify.mjs" --godot "$GODOT_BIN" --suite release --output "${GAMESMITH_VERIFY_OUTPUT:-summary}"
