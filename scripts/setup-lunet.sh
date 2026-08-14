#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned Lunet release. Runtime acquisition is the vendored, SHA-256-verified
# release fetcher (see scripts/lunet_fetch_release_<tag>.lua); this repo does
# not clone or compile Lunet. To test an unreleased upstream revision, build it
# yourself and point LUNET_BIN at it (see LUNET_PINNING.md).
LUNET_TAG="v0.9.2"
FETCHER="${LUNET_FETCHER:-$ROOT_DIR/scripts/lunet_fetch_release_${LUNET_TAG}.lua}"

if [ ! -f "$FETCHER" ]; then
    echo "Missing fetcher script: $FETCHER" >&2
    exit 1
fi

if command -v lua >/dev/null 2>&1; then
    LUA_RUN=(lua)
elif command -v luajit >/dev/null 2>&1; then
    LUA_RUN=(luajit)
elif command -v xmake >/dev/null 2>&1; then
    LUA_RUN=(xmake lua)
else
    echo "No Lua interpreter found to run the fetcher (need lua, luajit, or xmake)." >&2
    exit 1
fi

cd "$ROOT_DIR"
RUNTIME_PATH="$("${LUA_RUN[@]}" "$FETCHER" | tail -n 1)"

if [ ! -x "$RUNTIME_PATH" ]; then
    echo "Fetcher did not produce an executable runtime: $RUNTIME_PATH" >&2
    exit 1
fi

echo "Prepared Lunet $LUNET_TAG runtime"
echo "LUNET_BIN=$ROOT_DIR/$RUNTIME_PATH"
