#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/scripts/lunet-env.sh"

export DMZ_HOST=${DMZ_HOST:-127.0.0.1}
export BACKFLOW_PORT=${BACKFLOW_PORT:-9000}
export SERVICE_NAME=${SERVICE_NAME:-echo}

detect_cores() {
    getconf _NPROCESSORS_ONLN 2>/dev/null || \
    nproc 2>/dev/null || \
    sysctl -n hw.ncpu 2>/dev/null || \
    echo 2
}

DEFAULT_WORKERS=$(( $(detect_cores) * 2 ))
if [ "$DEFAULT_WORKERS" -lt 2 ]; then
    DEFAULT_WORKERS=2
fi
export WORKERS=${WORKERS:-$DEFAULT_WORKERS}

"$LUNET_BIN" "$ROOT_DIR/app/echo/main.lua"
