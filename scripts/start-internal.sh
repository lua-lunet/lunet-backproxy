#!/usr/bin/env bash
set -euo pipefail

export DMZ_HOST=${DMZ_HOST:-127.0.0.1}
export BACKFLOW_PORT=${BACKFLOW_PORT:-9000}
export SERVICE_NAME=${SERVICE_NAME:-conduit}
export WORKERS=${WORKERS:-4}

# Database
export DB_PATH=${DB_PATH:-.tmp/conduit.sqlite3}

# SQLite driver from lunet build
SQLITE_SO=$(find ./lunet/build -name 'sqlite3.so' -type f 2>/dev/null | head -1)
if [ -n "$SQLITE_SO" ]; then
    export LUA_CPATH="$(dirname "$SQLITE_SO")/?.so;;"
fi

./lunet/build/lunet app/internal/main.lua
