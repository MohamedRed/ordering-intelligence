#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/run-go-tests.sh"
"$SCRIPT_DIR/run-node-tests.sh"
"$SCRIPT_DIR/run-flutter-tests.sh"
