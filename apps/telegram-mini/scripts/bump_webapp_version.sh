#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_HTML="$ROOT_DIR/web/index.html"

if [[ ! -f "$INDEX_HTML" ]]; then
  echo "index.html not found at $INDEX_HTML" >&2
  exit 1
fi

VERSION="${1:-$(date -u +%Y%m%d%H%M%S)}"
export WEBAPP_VERSION="$VERSION"

perl -0777 -i -pe 's/(<meta name="webapp-version" content=")[^"]*(")/$1$ENV{WEBAPP_VERSION}$2/g' "$INDEX_HTML"

printf '%s\n' "$VERSION" > "$ROOT_DIR/web/webapp_version.txt"

echo "Webapp version set to $VERSION"
