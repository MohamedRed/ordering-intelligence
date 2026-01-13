#!/usr/bin/env bash
# Simple end-to-end smoke for menu-ingestion: start -> upload -> submit -> poll status.
# Requirements: gcloud CLI, python3, curl. Default targets dev service/SA; override via env.
set -euo pipefail

SERVICE_URL="${SERVICE_URL:-https://menu-ingestion-f2qwyitacq-uc.a.run.app}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-menu-ingestion-dev@ordering-intelligence.iam.gserviceaccount.com}"
STORE_ID="${STORE_ID:-smoke-store-$(date +%s)}"
POLL_MAX="${POLL_MAX:-10}"
POLL_SLEEP="${POLL_SLEEP:-5}"

echo "Using service: $SERVICE_URL"
echo "Service account: $SERVICE_ACCOUNT"
echo "Store: $STORE_ID"

echo "Getting ID token..."
TOKEN="$(gcloud auth print-identity-token --impersonate-service-account="${SERVICE_ACCOUNT}" --audiences="${SERVICE_URL}")"

echo "Starting ingest..."
START_JSON="$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "{\"restaurantId\":\"${STORE_ID}\",\"pageCount\":1}" \
  "${SERVICE_URL}/ingest/start")"
echo "Start response: $START_JSON"

JOB_ID="$(python3 - <<'PY' "$START_JSON"
import json,sys
data=json.loads(sys.argv[1])
print(data["jobId"])
PY)"
UPLOAD_URL="$(python3 - <<'PY' "$START_JSON"
import json,sys
data=json.loads(sys.argv[1])
print(data["uploadUrls"][0])
PY)"

echo "Job: $JOB_ID"
echo "Uploading synthetic menu image..."
TMP_IMG="$(mktemp /tmp/menu-smoke-XXXX.jpg)"
python3 - <<'PY' "$TMP_IMG"
from PIL import Image, ImageDraw, ImageFont
import pathlib, sys, random
path = pathlib.Path(sys.argv[1])
img = Image.new("RGB", (900, 1200), (249, 247, 241))
draw = ImageDraw.Draw(img)
title = "Smoke Test Menu"
items = [
    ("Cheeseburger", "$9.99"),
    ("Veggie Wrap", "$8.49"),
    ("Chicken Tenders", "$10.49"),
    ("Fries (Large)", "$3.99"),
    ("Soda", "$1.99"),
    ("Oil Filter", "$7.49"),
    ("Spark Plug", "$5.99"),
]
draw.rectangle([40, 40, 860, 180], fill=(34, 34, 34))
draw.text((60, 90), title, fill=(255, 255, 255), font=ImageFont.load_default())
y = 240
for name, price in items:
    draw.text((80, y), name, fill=(20, 20, 20), font=ImageFont.load_default())
    draw.text((680, y), price, fill=(20, 20, 20), font=ImageFont.load_default())
    y += 80
img.save(path, format="JPEG", quality=90)
print(path)
PY
curl -s -X PUT -H 'Content-Type: image/jpeg' --upload-file "${TMP_IMG}" "${UPLOAD_URL}" >/dev/null
rm -f "${TMP_IMG}"

echo "Submitting job..."
SUBMIT_JSON="$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "{\"jobId\":\"${JOB_ID}\"}" \
  "${SERVICE_URL}/ingest/submit")"
echo "Submit response: $SUBMIT_JSON"

echo "Polling status..."
for i in $(seq 1 "${POLL_MAX}"); do
  STATUS_JSON="$(curl -s -H "Authorization: Bearer ${TOKEN}" "${SERVICE_URL}/ingest/${JOB_ID}")"
  STATUS="$(python3 - <<'PY' "$STATUS_JSON"
import json,sys
try:
  print(json.loads(sys.argv[1]).get("status","unknown"))
except Exception:
  print("error")
PY)"
  echo "  poll $i: $STATUS"
  if [[ "$STATUS" == "ready" || "$STATUS" == "error" ]]; then
    echo "Final status: $STATUS"
    echo "Full payload: $STATUS_JSON"
    exit 0
  fi
  sleep "${POLL_SLEEP}"
done

echo "Polling exhausted without terminal state."
exit 1
