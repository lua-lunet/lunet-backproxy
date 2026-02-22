#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/scripts/lunet-env.sh"
source "$ROOT_DIR/scripts/runtime-checks-env.sh"

# C-module loader validation runs first when requested or always as a
# lightweight smoke-test so "compiles but can't load" failures surface
# before the full suite.
BACKPROXY_CMODULE_CHECK="${BACKPROXY_CMODULE_CHECK:-1}"
if [ "$BACKPROXY_CMODULE_CHECK" = "1" ]; then
    echo "Running C-module loader validation..."
    "$LUNET_BIN" "$ROOT_DIR/test/test_cmodule_loader.lua"
fi

tests=(
    "test/test_peer_guard.lua"
    "test/test_unix_loop.lua"
    "test/test_tcp_loop.lua"
    "test/test_combined_loops.lua"
    "test/test_hardening.lua"
)

for t in "${tests[@]}"; do
    echo "Running $t..."
    "$LUNET_BIN" "$ROOT_DIR/$t"
done

ENABLE_CONDUIT_DEMO="${ENABLE_CONDUIT_DEMO:-1}"
if [ "$ENABLE_CONDUIT_DEMO" = "1" ]; then
    echo "Running integration test (conduit demo enabled)..."
    export DB_PATH="$ROOT_DIR/.tmp/test_integration.sqlite3"
    rm -f "$DB_PATH"
    "$LUNET_BIN" "$ROOT_DIR/test/test_integration.lua"
else
    echo "Skipping conduit integration test (ENABLE_CONDUIT_DEMO=$ENABLE_CONDUIT_DEMO)"
fi

echo "All tests passed."
