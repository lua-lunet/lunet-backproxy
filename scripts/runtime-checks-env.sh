#!/usr/bin/env bash
# runtime-checks-env.sh
#
# Optional diagnostic knobs for language runtimes used by lunet-backproxy.
# Source this file before launching lunet or running tests to activate
# memory-safety and loader checks.  All knobs are off by default and
# controlled by the env vars documented below.
#
# Usage:
#   source scripts/runtime-checks-env.sh   # sets env vars only
#   xmake test                              # benefits from them
#
# Knobs:
#   BACKPROXY_MALLOC_DEBUG=1   Enable Apple allocator debugging (macOS only)
#   BACKPROXY_ASAN_HINTS=1     Print guidance for running under ASan/TSan
#   BACKPROXY_CMODULE_CHECK=1  Run Lua C-module loader validation before tests

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. macOS allocator debugging (MallocScribble et al.)
#    These env vars are read by the system allocator on Apple platforms and
#    expose use-after-free, heap corruption, and uninitialised reads at the
#    cost of runtime speed.  They are no-ops on Linux.
#    Reference: man malloc (macOS), Technical Note TN2124.
# ---------------------------------------------------------------------------
if [ "${BACKPROXY_MALLOC_DEBUG:-0}" = "1" ]; then
    case "$(uname -s)" in
        Darwin)
            export MallocScribble=1
            export MallocPreScribble=1
            export MallocGuardEdges=1
            export MallocStackLogging=lite
            export MallocCheckHeapStart=100
            export MallocCheckHeapEach=100
            echo "[runtime-checks] macOS allocator debugging ENABLED"
            echo "  MallocScribble=1        (scribble freed memory with 0x55)"
            echo "  MallocPreScribble=1     (scribble allocated memory with 0xAA)"
            echo "  MallocGuardEdges=1      (guard pages around large allocations)"
            echo "  MallocStackLogging=lite (lightweight stack logging)"
            echo "  MallocCheckHeapStart=100 MallocCheckHeapEach=100"
            ;;
        *)
            echo "[runtime-checks] BACKPROXY_MALLOC_DEBUG=1 ignored (not macOS)"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 2. ASan / TSan guidance
#    Lunet's C runtime and any C modules (.so) can be built with sanitizers.
#    This block does not enable them (they require a recompile) but prints
#    the exact steps so the developer knows what to do.
#
#    Rust note: -Zsanitizer={address,thread} requires nightly and is the
#    standard cargo-fuzz / sanitizer workflow for Rust code interfacing with
#    C libraries.  This project is pure Lua/C, but the guidance is included
#    for completeness if Lunet ever ships Rust components.
# ---------------------------------------------------------------------------
if [ "${BACKPROXY_ASAN_HINTS:-0}" = "1" ]; then
    echo ""
    echo "[runtime-checks] ASan/TSan build guidance"
    echo "  Lunet (C, via xmake):"
    echo "    cd .tmp/src/lunet-v0.1.2"
    echo "    xmake f -P . -m release --lunet_asan=y"
    echo "    xmake build -P ."
    echo "    export LUNET_BIN=\$(pwd)/build/release/lunet-run"
    echo ""
    echo "  Rust sanitizers (nightly required, for reference):"
    echo "    RUSTFLAGS='-Zsanitizer=address' cargo +nightly build"
    echo "    RUSTFLAGS='-Zsanitizer=thread'  cargo +nightly build"
    echo ""
    echo "  Then re-run:  xmake test"
fi

# ---------------------------------------------------------------------------
# 3. C-module loader check flag
#    When BACKPROXY_CMODULE_CHECK=1, the test runner will execute
#    test/test_cmodule_loader.lua first to validate that all .so modules
#    resolve via package.cpath and export the expected luaopen_* symbols.
# ---------------------------------------------------------------------------
export BACKPROXY_CMODULE_CHECK="${BACKPROXY_CMODULE_CHECK:-0}"
