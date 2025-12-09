#!/usr/bin/env bash
set -euo pipefail

STORE_ID=${STORE_ID:-demo-store}
ORDER_SERVICE_URL=${ORDER_SERVICE_URL:-http://localhost:8082}

curl -s "${ORDER_SERVICE_URL}/stores/${STORE_ID}/menu/snapshot" \
  -H 'Accept: application/json' | jq '.'
