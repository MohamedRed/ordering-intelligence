#!/usr/bin/env bash
set -euo pipefail

# End-to-end helper for Order Status Comms:
# - fetch ElevenLabs API key from GCP Secret Manager (no printing)
# - create a new ElevenLabs agent versioning branch
# - sync order-related tools from local manifest via the ElevenLabs Python SDK
# - patch the new branch with a local agent config JSON
#
# Usage:
#   elevenlabs/scripts/order_status_comms_setup.sh \
#     --agent-id agent_... \
#     --project ordering-intelligence

PROJECT_ID="ordering-intelligence"
ELEVENLABS_SECRET_NAME="elevenlabs-api-key"
AGENT_ID=""
AGENT_CONFIG="elevenlabs/agent_configs/Order-taker.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --elevenlabs-secret)
      ELEVENLABS_SECRET_NAME="${2:-}"
      shift 2
      ;;
    --agent-id)
      AGENT_ID="${2:-}"
      shift 2
      ;;
    --agent-config)
      AGENT_CONFIG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --agent-id agent_... [--project PROJECT] [--elevenlabs-secret SECRET] [--agent-config PATH]" >&2
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$AGENT_ID" ]]; then
  echo "--agent-id is required" >&2
  exit 2
fi

BRANCH_NAME="feature/order-status-comms-$(date +%Y%m%d-%H%M%S)"
OUT_DIR="elevenlabs/tmp_local_current/feature"
OUT_FILE="${OUT_DIR}/${BRANCH_NAME//\\//_}.branch.json"

mkdir -p "$OUT_DIR"

# Do not echo the API key.
export ELEVENLABS_API_KEY="$(gcloud secrets versions access latest --secret="$ELEVENLABS_SECRET_NAME" --project="$PROJECT_ID")"

python3 elevenlabs/scripts/create_agent_branch.py \
  --agent-id "$AGENT_ID" \
  --name "$BRANCH_NAME" \
  --description "Order status comms tools + prompt updates" \
  --output "$OUT_FILE" \
  --force

BRANCH_ID="$(python3 -c "import json; print(json.load(open('$OUT_FILE','r',encoding='utf-8'))['branch_id'])")"

python3 elevenlabs/scripts/sync_tools_from_manifest.py --only tool_configs/order_

python3 elevenlabs/scripts/update_agent_branch_from_config.py \
  --agent-id "$AGENT_ID" \
  --branch-id "$BRANCH_ID" \
  --config "$AGENT_CONFIG"

echo "Done."
echo "- branch_name: $BRANCH_NAME"
echo "- branch_id: $BRANCH_ID"
echo "- branch_file: $OUT_FILE"

