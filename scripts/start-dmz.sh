#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/scripts/lunet-env.sh"

export UNIX_SOCKET=${UNIX_SOCKET:-/tmp/backproxy.sock}
export BACKFLOW_HOST=${BACKFLOW_HOST:-127.0.0.1}
export BACKFLOW_PORT=${BACKFLOW_PORT:-9000}
export SERVICE_NAME=${SERVICE_NAME:-conduit}

"$LUNET_BIN" "$ROOT_DIR/app/dmz/main.lua"
