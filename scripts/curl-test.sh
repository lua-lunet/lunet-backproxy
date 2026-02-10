#!/usr/bin/env bash
set -euo pipefail

echo "=== Test 1: DMZ health (direct via unix socket) ==="
curl -v --max-time 5 --unix-socket /tmp/backproxy.sock http://localhost/health 2>&1 || echo "FAIL"
echo
echo "=== Test 2: DMZ health via NGINX (TLS) ==="
curl -k -v --max-time 5 https://localhost/health 2>&1 || echo "FAIL"
echo
echo "=== Test 3: Conduit API via full chain ==="
curl -k -v --max-time 5 https://localhost/api/tags 2>&1 || echo "FAIL (is Conduit running on :3000?)"
echo
