#!/usr/bin/env bash
# Reset TecDoc tools in ElevenLabs using the official Python SDK (no CLI).
#
# This is intended to reset ONLY the TecDoc tool set (32 configs), and by default it will only
# delete existing tools that match those names (safer than deleting all workspace tools).
#
# Examples:
#   ELEVENLABS_API_KEY=... elevenlabs/scripts/reset_tecdoc_tools.sh
#   ELEVENLABS_API_KEY=... elevenlabs/scripts/reset_tecdoc_tools.sh --delete-mode all
#   ELEVENLABS_API_KEY=... elevenlabs/scripts/reset_tecdoc_tools.sh --output-manifest elevenlabs/tools.tecdoc.generated.json

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  echo "ELEVENLABS_API_KEY is not set. Aborting." >&2
  exit 1
fi

DELETE_MODE="matching"
OUTPUT_MANIFEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-mode)
      DELETE_MODE="${2:-}"
      shift 2
      ;;
    --output-manifest)
      OUTPUT_MANIFEST="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--delete-mode matching|all|none] [--output-manifest path]" >&2
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUTPUT_MANIFEST" ]]; then
  OUTPUT_MANIFEST="$ROOT/tools.tecdoc.generated.json"
fi

echo "==> Resetting TecDoc tools via SDK"
echo "==> config_dir: $ROOT/tool_configs_clean"
echo "==> delete_mode: $DELETE_MODE"
echo "==> output_manifest: $OUTPUT_MANIFEST"

python3 "$ROOT/scripts/reset_tools_from_local.py" \
  --config-dir "$ROOT/tool_configs_clean" \
  --delete-mode "$DELETE_MODE" \
  --output-manifest "$OUTPUT_MANIFEST"

echo "Done. Refresh the ElevenLabs web console; you should see the TecDoc clean set."
