#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/scripts/lunet-env.sh"

tests=(
    "test/test_unix_loop.lua"
    "test/test_tcp_loop.lua"
    "test/test_combined_loops.lua"
)

for t in "${tests[@]}"; do
    echo "Running $t..."
    "$LUNET_BIN" "$ROOT_DIR/$t"
done

echo "Running integration test..."
export DB_PATH="$ROOT_DIR/.tmp/test_integration.sqlite3"
rm -f "$DB_PATH"
"$LUNET_BIN" "$ROOT_DIR/test/test_integration.lua"

echo "All tests passed."
