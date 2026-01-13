#!/bin/bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULES=$(rg --files -g 'go.mod' "$ROOT_DIR" | rg -v '^'"$ROOT_DIR"'/tmp/')

if [[ -z "$MODULES" ]]; then
  echo "No Go modules found."
  exit 0
fi

failures=()
while IFS= read -r mod; do
  [[ -z "$mod" ]] && continue
  dir="$(dirname "$mod")"
  echo "==> go test ./... in $dir"
  if ! (cd "$dir" && go test ./...); then
    failures+=("$dir")
  fi
  echo ""
done <<< "$MODULES"

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "FAILED modules:"
  printf '%s\n' "${failures[@]}"
  exit 1
fi
