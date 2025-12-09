#!/usr/bin/env bash
# Reset TecDoc tools in ElevenLabs: delete everything remote, then push the 32 clean configs.
# Requirements:
#   - ELEVENLABS_API_KEY set (unrestricted)
#   - elevenlabs CLI installed and logged in
#   - tool_configs/ contains the 32 canonical webhook configs

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${ROOT}/tmp_tecdoc_tools.XXXX")"

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  echo "ELEVENLABS_API_KEY is not set. Aborting." >&2
  exit 1
fi

echo "==> Pulling all remote tools into temp dir ${TMP_DIR}"
(
  cd "$TMP_DIR"
  ELEVENLABS_NO_TTY=1 ELEVENLABS_API_KEY="$ELEVENLABS_API_KEY" elevenlabs tools pull --all --no-ui --output-dir "$TMP_DIR" || true
)

echo "==> Deleting all remote tools (and temp configs)"
(
  cd "$TMP_DIR"
  ELEVENLABS_NO_TTY=1 ELEVENLABS_API_KEY="$ELEVENLABS_API_KEY" elevenlabs tools delete --all --no-ui || true
)

echo "==> Cleaning temp dir"
rm -rf "$TMP_DIR"

echo "==> Rebuilding tools.json from local tool_configs/"
(
  cd "$ROOT"
  python - <<'PY'
import os, json, glob
root = os.getcwd()
files = sorted(glob.glob(os.path.join("tool_configs", "*.json")))
entries = [{"path": f} for f in files]
with open("tools.json", "w") as f:
    json.dump({"tools": entries}, f, indent=4)
print(f"tools.json updated with {len(entries)} tools")
PY
)

echo "==> Pushing the 32 clean tools to ElevenLabs"
(
  cd "$ROOT"
  ELEVENLABS_NO_TTY=1 ELEVENLABS_API_KEY="$ELEVENLABS_API_KEY" elevenlabs tools push --no-ui
)

echo "Done. Refresh the ElevenLabs web console; you should see exactly the clean set."
