#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REQUESTS="${REQUESTS:-1500}"
ROUNDS="${ROUNDS:-6}"
CONCURRENCY="${CONCURRENCY:-24}"
MAX_TIME="${MAX_TIME:-5}"
TARGET_PATH="${TARGET_PATH:-/api/tags}"

OUT_DIR="${OUT_DIR:-$ROOT_DIR/.tmp/stress-compare-$(date +%Y%m%d_%H%M%S)}"
BASELINE_DIR="$OUT_DIR/baseline"
INSTRUMENTED_DIR="$OUT_DIR/instrumented"
mkdir -p "$BASELINE_DIR" "$INSTRUMENTED_DIR"

detect_instrumented_runtime() {
    if [ -n "${INSTRUMENTED_LUNET_BIN:-}" ] && [ -x "$INSTRUMENTED_LUNET_BIN" ]; then
        echo "$INSTRUMENTED_LUNET_BIN"
        return 0
    fi

    local os_part arch_part
    case "$(uname -s)" in
        Darwin) os_part="macosx" ;;
        Linux) os_part="linux" ;;
        *) return 1 ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch_part="arm64" ;;
        x86_64|amd64) arch_part="x86_64" ;;
        *) return 1 ;;
    esac

    local candidate="/Users/Shared/lua-lunet/lunet/build/${os_part}/${arch_part}/debug/lunet-run"
    if [ -x "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

extract_metric() {
    local file="$1" key="$2"
    sed -n "s/.*${key}=\\([^ ]*\\).*/\\1/p" "$file" | tail -1
}

echo "Running baseline (non-instrumented pinned runtime)..."
MODE_LABEL="baseline" \
REQUESTS="$REQUESTS" \
ROUNDS="$ROUNDS" \
CONCURRENCY="$CONCURRENCY" \
MAX_TIME="$MAX_TIME" \
TARGET_PATH="$TARGET_PATH" \
HTTP_PORT=18310 \
BACKFLOW_PORT=19310 \
OUT_DIR="$BASELINE_DIR" \
"$ROOT_DIR/scripts/stress-real-e2e.sh"

INSTRUMENTED_BIN="$(detect_instrumented_runtime || true)"
if [ -z "$INSTRUMENTED_BIN" ]; then
    echo "Could not locate instrumented Lunet runtime. Set INSTRUMENTED_LUNET_BIN." >&2
    exit 2
fi

INSTRUMENTED_BIN_DIR="$(cd "$(dirname "$INSTRUMENTED_BIN")" && pwd)"
INSTRUMENTED_LUA_CPATH="${INSTRUMENTED_LUA_CPATH:-$INSTRUMENTED_BIN_DIR/?.so;$INSTRUMENTED_BIN_DIR/?/?.so;;}"

echo "Running instrumented runtime benchmark..."
LUNET_BIN="$INSTRUMENTED_BIN" \
LUA_CPATH="$INSTRUMENTED_LUA_CPATH" \
LUNET_RUNTIME_REF="${LUNET_RUNTIME_REF:-instrumented-local-build}" \
MODE_LABEL="instrumented" \
REQUESTS="$REQUESTS" \
ROUNDS="$ROUNDS" \
CONCURRENCY="$CONCURRENCY" \
MAX_TIME="$MAX_TIME" \
TARGET_PATH="$TARGET_PATH" \
HTTP_PORT=18311 \
BACKFLOW_PORT=19311 \
OUT_DIR="$INSTRUMENTED_DIR" \
"$ROOT_DIR/scripts/stress-real-e2e.sh"

BASELINE_SUMMARY="$BASELINE_DIR/summary.log"
INSTRUMENTED_SUMMARY="$INSTRUMENTED_DIR/summary.log"

baseline_rps="$(extract_metric "$BASELINE_SUMMARY" "rps")"
instrumented_rps="$(extract_metric "$INSTRUMENTED_SUMMARY" "rps")"
baseline_ok="$(extract_metric "$BASELINE_SUMMARY" "total_ok")"
instrumented_ok="$(extract_metric "$INSTRUMENTED_SUMMARY" "total_ok")"

if [ -z "$baseline_rps" ] || [ -z "$instrumented_rps" ]; then
    echo "Failed to parse summary metrics." >&2
    exit 3
fi

overhead_pct="$(awk -v base="$baseline_rps" -v inst="$instrumented_rps" 'BEGIN {
    if (base <= 0) {
        print "nan"
    } else {
        printf "%.2f", ((base - inst) / base) * 100
    }
}')"

echo "COMPARE baseline_rps=$baseline_rps instrumented_rps=$instrumented_rps overhead_pct=$overhead_pct baseline_ok=$baseline_ok instrumented_ok=$instrumented_ok"
echo "evidence_dir=$OUT_DIR"
