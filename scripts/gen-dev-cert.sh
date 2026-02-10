#!/usr/bin/env bash
set -euo pipefail

mkdir -p nginx/certs

# Self-signed dev cert for localhost
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout nginx/certs/dev.key \
  -out nginx/certs/dev.crt \
  -days 365 \
  -subj "/CN=localhost" 2>/dev/null

echo "Wrote nginx/certs/dev.crt and nginx/certs/dev.key"
