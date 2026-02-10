#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
TARGET_PATH="${1:-/health}"
REQUESTS="${REQUESTS:-50}"
CONCURRENCY="${CONCURRENCY:-10}"
MAX_TIME="${MAX_TIME:-3}"

target="${BASE_URL}${TARGET_PATH}"
echo "Gentle load test"
echo "target=${target}"
echo "requests=${REQUESTS} concurrency=${CONCURRENCY} max_time=${MAX_TIME}s"

results="$(
    seq 1 "$REQUESTS" | xargs -I{} -P"$CONCURRENCY" sh -c \
        "curl -sf --max-time \"$MAX_TIME\" \"$0\" >/dev/null && echo ok || echo fail" "$target"
)"

ok_count="$(printf "%s\n" "$results" | grep -c '^ok$' || true)"
fail_count="$(printf "%s\n" "$results" | grep -c '^fail$' || true)"

echo "result: ok=${ok_count} fail=${fail_count} total=${REQUESTS}"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
