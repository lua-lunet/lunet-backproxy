#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/scripts/lunet-env.sh"

HTTP_PORT="${HTTP_PORT:-18110}"
BACKFLOW_PORT="${BACKFLOW_PORT:-19110}"
WORKERS="${WORKERS:-2}"
REQUESTS="${REQUESTS:-20}"
CONCURRENCY="${CONCURRENCY:-2}"
MAX_TIME="${MAX_TIME:-5}"
ITERATIONS="${ITERATIONS:-10}"
DMZ_HOST="${DMZ_HOST:-127.0.0.1}"
SERVICE_NAME="${SERVICE_NAME:-echo}"

OUT_DIR="${OUT_DIR:-$ROOT_DIR/.tmp/repro-segfault-v010}"
mkdir -p "$OUT_DIR"
DMZ_LOG="$OUT_DIR/dmz.log"
ECHO_LOG="$OUT_DIR/echo.log"
LOAD_LOG="$OUT_DIR/load.log"

cleanup() {
    if [ -n "${ECHO_PID:-}" ]; then
        kill "$ECHO_PID" 2>/dev/null || true
        wait "$ECHO_PID" 2>/dev/null || true
    fi
    if [ -n "${DMZ_PID:-}" ]; then
        kill "$DMZ_PID" 2>/dev/null || true
        wait "$DMZ_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Starting DMZ + echo demo with Lunet v0.1.0 repro settings"
echo "http_port=$HTTP_PORT backflow_port=$BACKFLOW_PORT workers=$WORKERS"
echo "requests=$REQUESTS concurrency=$CONCURRENCY max_time=$MAX_TIME iterations=$ITERATIONS"
echo "logs: $OUT_DIR"

(
    export HTTP_HOST="$DMZ_HOST"
    export BACKFLOW_HOST="$DMZ_HOST"
    export HTTP_PORT
    export BACKFLOW_PORT
    export SERVICE_NAME
    "$LUNET_BIN" "$ROOT_DIR/app/dmz/main.lua"
) >"$DMZ_LOG" 2>&1 &
DMZ_PID=$!

sleep 1

(
    export DMZ_HOST
    export BACKFLOW_PORT
    export SERVICE_NAME
    export WORKERS
    "$LUNET_BIN" "$ROOT_DIR/app/echo/main.lua"
) >"$ECHO_LOG" 2>&1 &
ECHO_PID=$!

sleep 1

for i in $(seq 1 "$ITERATIONS"); do
    echo "iteration=$i" | tee -a "$LOAD_LOG"
    seq 1 "$REQUESTS" | TARGET="http://${DMZ_HOST}:${HTTP_PORT}/hello" MAX_TIME="$MAX_TIME" \
        xargs -n1 -P"$CONCURRENCY" sh -c \
        'curl -sf --max-time "$MAX_TIME" "$TARGET" >/dev/null && echo ok || echo fail' _ \
        >>"$LOAD_LOG"

    if ! kill -0 "$DMZ_PID" 2>/dev/null; then
        echo "DMZ crashed during iteration=$i" | tee -a "$LOAD_LOG"
        echo "See logs:"
        echo "  $DMZ_LOG"
        echo "  $ECHO_LOG"
        echo "  $LOAD_LOG"
        exit 139
    fi
done

echo "No crash observed in $ITERATIONS iterations." | tee -a "$LOAD_LOG"
