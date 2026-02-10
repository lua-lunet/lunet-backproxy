#!/usr/bin/env bash
set -euo pipefail

export UNIX_SOCKET=${UNIX_SOCKET:-/tmp/backproxy.sock}
export BACKFLOW_HOST=${BACKFLOW_HOST:-127.0.0.1}
export BACKFLOW_PORT=${BACKFLOW_PORT:-9000}
export SERVICE_NAME=${SERVICE_NAME:-conduit}

./lunet/build/lunet app/dmz/main.lua
