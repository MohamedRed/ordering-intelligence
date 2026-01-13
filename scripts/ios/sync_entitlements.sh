#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/apps/consumer/ios/Runner/Runner.entitlements"
XCSECRETS="$ROOT_DIR/apps/consumer/ios/Flutter/Secrets.xcconfig"

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Missing entitlements file: $ENTITLEMENTS"
  exit 1
fi

GROUP="${CONSUMER_APP_GROUP:-}"
if [[ -z "$GROUP" ]]; then
  GROUP="$(grep -E '^CONSUMER_APP_GROUP=' "$XCSECRETS" | cut -d'=' -f2- | tr -d '\r')"
fi

if [[ -z "$GROUP" ]]; then
  echo "CONSUMER_APP_GROUP not set. Set env var or update $XCSECRETS."
  exit 1
fi

/usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$ENTITLEMENTS" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $GROUP" "$ENTITLEMENTS"

echo "Updated App Group entitlements to $GROUP"
