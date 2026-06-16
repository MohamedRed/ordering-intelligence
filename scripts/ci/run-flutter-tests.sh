#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS=(admin business consumer driver telegram-mini)

for app in "${APPS[@]}"; do
  APP_DIR="$ROOT_DIR/apps/$app"
  echo "==> flutter analyze ($APP_DIR)"
  (cd "$APP_DIR" && flutter analyze)

  echo ""
  echo "==> flutter test ($APP_DIR)"
  (cd "$APP_DIR" && flutter test)
  echo ""
done
