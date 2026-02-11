#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED_LUNET_REF_DEFAULT="6303e54e3a52a6aed30bdff058d7d77535e076aa"
LUNET_REF="${LUNET_REF:-${LUNET_VERSION:-$PINNED_LUNET_REF_DEFAULT}}"

ref_slug() {
    printf "%s" "$1" | tr '/:' '__' | tr -c '[:alnum:]._-' '_'
}

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

REF_SLUG="$(ref_slug "$LUNET_REF")"
RUNTIME_DIR="$ROOT_DIR/.tmp/runtime/lunet-${REF_SLUG}"

"$ROOT_DIR/scripts/setup-lunet.sh"

export LUNET_BIN="$RUNTIME_DIR/bin/lunet"
export LUA_CPATH="$RUNTIME_DIR/lib/?.so;$RUNTIME_DIR/lib/?/?.so;;${LUA_CPATH:-}"
export LUNET_RUNTIME_REF="$LUNET_REF"
