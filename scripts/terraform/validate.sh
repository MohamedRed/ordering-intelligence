#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ENVS=("${@:-dev staging prod}")

for env in "${ENVS[@]}"; do
  echo "==> Validating terraform env: ${env}"
  pushd "${ROOT_DIR}/infrastructure/terraform/environments/${env}" >/dev/null
  terraform init -backend=false
  terraform validate
  popd >/dev/null
done

