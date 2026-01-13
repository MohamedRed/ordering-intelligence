#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/apps/consumer"

echo "==> flutter analyze ($APP_DIR)"
(cd "$APP_DIR" && flutter analyze)

echo ""
echo "==> flutter test ($APP_DIR)"
(cd "$APP_DIR" && flutter test)
