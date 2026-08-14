#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUNET_TAG="v0.9.2"

# Respect externally provided runtime binaries (e.g. instrumented Lunet builds).
if [ -n "${LUNET_BIN:-}" ] && [ -x "$LUNET_BIN" ]; then
    if [ -z "${LUA_CPATH:-}" ]; then
        LUNET_BIN_DIR="$(cd "$(dirname "$LUNET_BIN")" && pwd)"
        export LUA_CPATH="$LUNET_BIN_DIR/?.so;$LUNET_BIN_DIR/?/?.so;;"
    fi
    export LUNET_RUNTIME_REF="${LUNET_RUNTIME_REF:-external}"
    if (return 0 2>/dev/null); then
        return 0
    else
        exit 0
    fi
fi

"$ROOT_DIR/scripts/setup-lunet.sh" >/dev/null

export LUNET_BIN="$ROOT_DIR/.lunet/$LUNET_TAG/lunet-run"
export LUNET_RUNTIME_REF="$LUNET_TAG"
# No LUA_CPATH: the release archive is self-contained; lunet-run resolves
# lunet.so and lunet/*.so relative to its own directory.
