#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export DMZ_HOST="${DMZ_HOST:-dmz}"
export BACKFLOW_PORT="${BACKFLOW_PORT:-9000}"
export SERVICE_NAME="${SERVICE_NAME:-conduit}"
export WORKERS="${WORKERS:-2}"
export DB_PATH="${DB_PATH:-/opt/lunet-backproxy/.tmp/conduit.sqlite3}"

exec "$ROOT_DIR/scripts/start-internal.sh"
