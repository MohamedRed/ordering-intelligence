#!/usr/bin/env bash
# Placeholder smoke test for LiveKit hosted agent.
# Requires lk CLI, SIP credentials, and a test number configured.
# This script currently just checks that lk CLI is present.

set -euo pipefail

if ! command -v lk >/dev/null 2>&1; then
  echo "lk CLI not installed; skipping"
  exit 0
fi

echo "TODO: implement SIP call smoke test"
exit 0
