#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export HTTP_HOST="${HTTP_HOST:-0.0.0.0}"
export BACKFLOW_HOST="${BACKFLOW_HOST:-0.0.0.0}"
export HTTP_PORT="${HTTP_PORT:-8080}"
export BACKFLOW_PORT="${BACKFLOW_PORT:-9000}"
export SERVICE_NAME="${SERVICE_NAME:-echo}"
export UNIX_SOCKET="${UNIX_SOCKET:-/tmp/backproxy.sock}"
# Container DMZ binds 0.0.0.0 by design; perimeter controls live at the edge.
export LUNET_RUN_EXTRA_ARGS="--dangerously-skip-loopback-restriction"

exec "$ROOT_DIR/scripts/start-dmz.sh"
