#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE_LABEL="${MODE_LABEL:-baseline}"
TARGET_PATH="${TARGET_PATH:-/api/tags}"
REQUESTS="${REQUESTS:-1000}"
CONCURRENCY="${CONCURRENCY:-16}"
ROUNDS="${ROUNDS:-5}"
MAX_TIME="${MAX_TIME:-5}"
WORKERS="${WORKERS:-2}"
DB_POOL_SIZE="${DB_POOL_SIZE:-$WORKERS}"
HTTP_PORT="${HTTP_PORT:-18200}"
BACKFLOW_PORT="${BACKFLOW_PORT:-19200}"
SERVICE_NAME="${SERVICE_NAME:-conduit}"

if [ -z "${OUT_DIR:-}" ]; then
    OUT_DIR="$ROOT_DIR/.tmp/stress-${MODE_LABEL}-$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$OUT_DIR"

DMZ_LOG="$OUT_DIR/dmz.log"
INTERNAL_LOG="$OUT_DIR/internal.log"
SUMMARY_LOG="$OUT_DIR/summary.log"
RESULTS_LOG="$OUT_DIR/results.log"

source "$ROOT_DIR/scripts/lunet-env.sh"

if [ ! -x "${LUNET_BIN:-}" ]; then
    echo "Missing executable LUNET_BIN: ${LUNET_BIN:-unset}" >&2
    exit 2
fi

if [ "$(uname -s)" = "Darwin" ] && [ -f "/opt/homebrew/lib/libsodium.dylib" ]; then
    export DYLD_LIBRARY_PATH="/opt/homebrew/lib:${DYLD_LIBRARY_PATH:-}"
fi

port_listening() {
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

if port_listening "$HTTP_PORT" || port_listening "$BACKFLOW_PORT"; then
    echo "ERROR: HTTP_PORT=$HTTP_PORT or BACKFLOW_PORT=$BACKFLOW_PORT already listening; refusing to test a stale runtime" >&2
    exit 2
fi

HAVE_SETSID=0
if command -v setsid >/dev/null 2>&1; then
    HAVE_SETSID=1
fi

# Kill the whole process group so detached lunet-run children die too; a plain
# kill of the wrapper subshell PID lets lunet-run reparent to init and keep the
# ports held, which makes a later run silently test a stale runtime.
start_runtime() {
    if [ "$HAVE_SETSID" -eq 1 ]; then
        setsid "$@"
    else
        "$@"
    fi
}

cleanup() {
    local i
    if [ "$HAVE_SETSID" -eq 1 ]; then
        [ -n "${DMZ_PID:-}" ] && kill -- "-$DMZ_PID" 2>/dev/null || true
        [ -n "${INT_PID:-}" ] && kill -- "-$INT_PID" 2>/dev/null || true
    else
        # No setsid (macOS): target the exact launched command paths.
        pkill -f "$LUNET_BIN $ROOT_DIR/app/dmz/main.lua" 2>/dev/null || true
        pkill -f "$LUNET_BIN $ROOT_DIR/app/internal/main.lua" 2>/dev/null || true
    fi
    for _ in $(seq 1 20); do
        if ! port_listening "$HTTP_PORT" && ! port_listening "$BACKFLOW_PORT"; then
            break
        fi
        if [ "$HAVE_SETSID" -eq 1 ]; then
            [ -n "${DMZ_PID:-}" ] && kill -9 -- "-$DMZ_PID" 2>/dev/null || true
            [ -n "${INT_PID:-}" ] && kill -9 -- "-$INT_PID" 2>/dev/null || true
        else
            pkill -9 -f "$LUNET_BIN $ROOT_DIR/app/dmz/main.lua" 2>/dev/null || true
            pkill -9 -f "$LUNET_BIN $ROOT_DIR/app/internal/main.lua" 2>/dev/null || true
        fi
        sleep 0.5
    done
    if port_listening "$HTTP_PORT" || port_listening "$BACKFLOW_PORT"; then
        echo "WARNING: ports $HTTP_PORT/$BACKFLOW_PORT still bound after cleanup" >&2
    fi
    [ -n "${DMZ_PID:-}" ] && wait "$DMZ_PID" 2>/dev/null || true
    [ -n "${INT_PID:-}" ] && wait "$INT_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "mode=$MODE_LABEL target=$TARGET_PATH requests=$REQUESTS rounds=$ROUNDS concurrency=$CONCURRENCY" | tee "$SUMMARY_LOG"
echo "lunet_bin=$LUNET_BIN runtime_ref=${LUNET_RUNTIME_REF:-unknown}" | tee -a "$SUMMARY_LOG"
echo "out_dir=$OUT_DIR" | tee -a "$SUMMARY_LOG"

(
    cd "$ROOT_DIR"
    export HTTP_HOST=127.0.0.1
    export BACKFLOW_HOST=127.0.0.1
    export HTTP_PORT
    export BACKFLOW_PORT
    export SERVICE_NAME
    export UNIX_SOCKET="$OUT_DIR/backproxy.sock"
    start_runtime "$LUNET_BIN" "$ROOT_DIR/app/dmz/main.lua"
) >"$DMZ_LOG" 2>&1 &
DMZ_PID=$!

(
    cd "$ROOT_DIR"
    export DMZ_HOST=127.0.0.1
    export BACKFLOW_PORT
    export SERVICE_NAME
    export WORKERS
    export DB_POOL_SIZE
    export DB_PATH="$OUT_DIR/conduit.sqlite3"
    export JWT_SECRET='stress-dev-secret'
    start_runtime "$LUNET_BIN" "$ROOT_DIR/app/internal/main.lua"
) >"$INTERNAL_LOG" 2>&1 &
INT_PID=$!

ready=0
for _ in $(seq 1 80); do
    if curl -sf --max-time 2 "http://127.0.0.1:${HTTP_PORT}${TARGET_PATH}" >/dev/null; then
        ready=1
        break
    fi
    sleep 0.25
done

if [ "$ready" -ne 1 ]; then
    echo "Service chain not ready" | tee -a "$SUMMARY_LOG"
    tail -n 80 "$DMZ_LOG" || true
    tail -n 80 "$INTERNAL_LOG" || true
    exit 1
fi

start_ts="$(date +%s)"
rounds_run=0
total_ok=0
total_fail=0
runtime_alive=1

for round in $(seq 1 "$ROUNDS"); do
    rounds_run="$round"
    echo "round=$round" | tee -a "$RESULTS_LOG"

    set +e
    load_out="$(
        cd "$ROOT_DIR" && \
        BASE_URL="http://127.0.0.1:${HTTP_PORT}" \
        REQUESTS="$REQUESTS" \
        CONCURRENCY="$CONCURRENCY" \
        MAX_TIME="$MAX_TIME" \
        scripts/docker/load-gentle.sh "$TARGET_PATH" 2>&1
    )"
    load_rc=$?
    set -e

    printf "%s\n" "$load_out" | tee -a "$RESULTS_LOG"
    ok_round="$(printf "%s\n" "$load_out" | sed -n 's/.*ok=\([0-9][0-9]*\).*/\1/p' | tail -1)"
    fail_round="$(printf "%s\n" "$load_out" | sed -n 's/.*fail=\([0-9][0-9]*\).*/\1/p' | tail -1)"
    ok_round="${ok_round:-0}"
    fail_round="${fail_round:-$REQUESTS}"

    total_ok=$((total_ok + ok_round))
    total_fail=$((total_fail + fail_round))

    if ! kill -0 "$DMZ_PID" 2>/dev/null || ! kill -0 "$INT_PID" 2>/dev/null; then
        runtime_alive=0
        break
    fi

    if [ "$load_rc" -ne 0 ]; then
        # Continue rounds to gather stronger signal, but keep failure counts.
        :
    fi
done

end_ts="$(date +%s)"
duration_s=$((end_ts - start_ts))
if [ "$duration_s" -lt 1 ]; then
    duration_s=1
fi

rps="$(awk -v ok="$total_ok" -v d="$duration_s" 'BEGIN { printf "%.2f", (ok / d) }')"
health_out="$(curl -sf --max-time 5 "http://127.0.0.1:${HTTP_PORT}/health" || true)"

status="PASS"
if [ "$runtime_alive" -ne 1 ] || [ "$total_fail" -ne 0 ]; then
    status="FAIL"
fi

if rg -n "BK_FAIL|ERROR: AddressSanitizer|Segmentation fault|Bus error|assert|panic" "$DMZ_LOG" "$INTERNAL_LOG" -S >"$OUT_DIR/fault_hits.log"; then
    status="FAIL"
fi

summary_line="SUMMARY mode=$MODE_LABEL rounds_run=$rounds_run requests_per_round=$REQUESTS concurrency=$CONCURRENCY total_ok=$total_ok total_fail=$total_fail duration_s=$duration_s rps=$rps runtime_alive=$runtime_alive status=$status"
echo "$summary_line" | tee -a "$SUMMARY_LOG"
echo "health=${health_out}" | tee -a "$SUMMARY_LOG"
echo "evidence_dir=$OUT_DIR" | tee -a "$SUMMARY_LOG"

if [ "$status" != "PASS" ]; then
    exit 1
fi
