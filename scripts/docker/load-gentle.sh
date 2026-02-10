#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
TARGET_PATH="${1:-/health}"
REQUESTS="${REQUESTS:-10}"
CONCURRENCY="${CONCURRENCY:-1}"
MAX_TIME="${MAX_TIME:-5}"

target="${BASE_URL}${TARGET_PATH}"
echo "Gentle load test"
echo "target=${target}"
echo "requests=${REQUESTS} concurrency=${CONCURRENCY} max_time=${MAX_TIME}s"

results="$(
    seq 1 "$REQUESTS" | TARGET="$target" MAX_TIME="$MAX_TIME" \
        xargs -n1 -P"$CONCURRENCY" sh -c \
        'curl -sf --max-time "$MAX_TIME" "$TARGET" >/dev/null && echo ok || echo fail' _
)"

ok_count="$(printf "%s\n" "$results" | grep -c '^ok$' || true)"
fail_count="$(printf "%s\n" "$results" | grep -c '^fail$' || true)"

echo "result: ok=${ok_count} fail=${fail_count} total=${REQUESTS}"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
