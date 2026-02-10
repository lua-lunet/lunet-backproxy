#!/usr/bin/env bash
set -euo pipefail

# Run nginx using local config
nginx -c "$(pwd)/nginx/nginx.conf" -p "$(pwd)/nginx"
