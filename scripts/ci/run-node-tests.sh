#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PACKAGES=(
  "backend/services/agent-customization"
  "backend/services/channel-comms"
  "backend/services/menu-ingestion"
  "backend/services/notification-service"
  "backend/services/onboarding"
  "backend/services/payments-service"
  "backend/services/pos-export"
  "backend/libs/voice-agent-config"
  "backend/services/voice-agent-worker"
)

has_script() {
  local package_json="$1"
  local script_name="$2"
  node -e "const p=require(process.argv[1]); process.exit(p.scripts && p.scripts[process.argv[2]] ? 0 : 1)" "$package_json" "$script_name"
}

for package_dir in "${PACKAGES[@]}"; do
  abs_dir="$ROOT_DIR/$package_dir"
  package_json="$abs_dir/package.json"
  echo "==> npm checks in $package_dir"
  (cd "$abs_dir" && npm ci)
  (cd "$abs_dir" && npm audit --omit=dev --audit-level=high)

  if has_script "$package_json" lint; then
    (cd "$abs_dir" && npm run lint)
  fi

  if has_script "$package_json" build; then
    (cd "$abs_dir" && npm run build)
  fi

  if has_script "$package_json" test; then
    (cd "$abs_dir" && npm test)
  fi
  echo ""
done
