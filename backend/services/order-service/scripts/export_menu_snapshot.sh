#!/usr/bin/env bash
set -euo pipefail

STORE_ID=${STORE_ID:-demo-store}
ORDER_SERVICE_URL=${ORDER_SERVICE_URL:-http://localhost:8082}
OUT_FILE=${OUT_FILE:-menu-${STORE_ID}.json}

curl -s "${ORDER_SERVICE_URL}/stores/${STORE_ID}/menu/snapshot" \
  -H "Accept: application/json" \
  -o "$OUT_FILE"

echo "Saved menu snapshot to $OUT_FILE"
