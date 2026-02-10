#!/usr/bin/env bash
set -euo pipefail

HTTP_PORT=${HTTP_PORT:-8080}

echo "=== Test 1: DMZ health (direct HTTP) ==="
curl -v --max-time 5 "http://127.0.0.1:${HTTP_PORT}/health" 2>&1 || echo "FAIL"
echo
echo "=== Test 2: Conduit API via full chain ==="
curl -v --max-time 5 "http://127.0.0.1:${HTTP_PORT}/api/tags" 2>&1 || echo "FAIL"
echo
echo "=== Test 3: optional unix socket health ==="
if [ -S /tmp/backproxy.sock ]; then
    curl -v --max-time 5 --unix-socket /tmp/backproxy.sock http://localhost/health 2>&1 || echo "FAIL"
else
    echo "SKIP (no /tmp/backproxy.sock present)"
fi
echo
