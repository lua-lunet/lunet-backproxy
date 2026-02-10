#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUNET_VERSION="${LUNET_VERSION:-v0.1.0}"
RUNTIME_DIR="$ROOT_DIR/.tmp/runtime/lunet-${LUNET_VERSION}"

"$ROOT_DIR/scripts/setup-lunet.sh"

export LUNET_BIN="$RUNTIME_DIR/bin/lunet"
export LUA_CPATH="$RUNTIME_DIR/lib/?.so;$RUNTIME_DIR/lib/?/?.so;;${LUA_CPATH:-}"
