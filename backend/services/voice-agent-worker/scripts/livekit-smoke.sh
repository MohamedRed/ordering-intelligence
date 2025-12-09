#!/usr/bin/env bash
set -euo pipefail

# Minimal smoke: place a synthetic order via LiveKit SIP participant create.

if ! command -v lk >/dev/null 2>&1; then
  echo "lk CLI not installed; skipping"
  exit 0
fi

# Required env: LK_PROJECT, ROOM_NAME, PARTICIPANT_NAME, SIP_TRUNK, SIP_NUMBER
ROOM_NAME=${ROOM_NAME:-smoke-room}
PARTICIPANT_NAME=${PARTICIPANT_NAME:-smoke-tester}
SIP_TRUNK=${SIP_TRUNK:-}
SIP_NUMBER=${SIP_NUMBER:-}

if [ -z "$SIP_TRUNK" ] || [ -z "$SIP_NUMBER" ]; then
  echo "SIP_TRUNK or SIP_NUMBER not set; skipping smoke"
  exit 0
fi

set -x
lk sip participant create \
  --trunk-id "$SIP_TRUNK" \
  --from "$SIP_NUMBER" \
  --to "$SIP_NUMBER" \
  --room-name "$ROOM_NAME" \
  --participant-identity "$PARTICIPANT_NAME" \
  --participant-name "$PARTICIPANT_NAME"

echo "LiveKit SIP participant create invoked (check LK dashboard for call)."
