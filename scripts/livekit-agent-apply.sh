#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: livekit-agent-apply.sh <environment> [--rotate] [--project <project-name>] [--region <lk-region>]

Automates LiveKit Cloud agent deployment for the voice-agent worker.

Examples:
  # Build + deploy the existing agent for staging
  ./scripts/livekit-agent-apply.sh staging

  # Rotate the dev agent (delete + create) while reusing the free-tier slot
  ./scripts/livekit-agent-apply.sh dev --rotate

Environment variables:
  LIVEKIT_PROJECT   Override the LiveKit project alias configured in the CLI.
  LIVEKIT_REGION    Region used when creating a hosted agent (default: us-east).
  LIVEKIT_API_KEY / LIVEKIT_API_SECRET / LIVEKIT_URL
                    Required for lk CLI authentication in CI.
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

ENVIRONMENT="$1"
shift

ROTATE=false
PROJECT_OVERRIDE=""
LK_REGION="${LIVEKIT_REGION:-us-east}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rotate)
      ROTATE=true
      shift
      ;;
    --project)
      PROJECT_OVERRIDE="$2"
      shift 2
      ;;
    --region)
      LK_REGION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="${ROOT_DIR}/backend/services/voice-agent-worker"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

case "${ENVIRONMENT}" in
  dev)
    DEFAULT_PROJECT="ordering-intelligence-dev"
    ;;
  staging)
    DEFAULT_PROJECT="ordering-intelligence-staging"
    ;;
  prod|production)
    DEFAULT_PROJECT="ordering-intelligence"
    ENVIRONMENT="prod"
    ;;
  *)
    echo "[livekit] Unknown environment '${ENVIRONMENT}'" >&2
    exit 1
    ;;
esac

LIVEKIT_PROJECT="${PROJECT_OVERRIDE:-${LIVEKIT_PROJECT:-${DEFAULT_PROJECT}}}"

if ! command -v lk >/dev/null 2>&1; then
  echo "[livekit] The LiveKit CLI (lk) is required. Install from https://docs.livekit.io/home/cli/." >&2
  exit 1
fi

echo "[livekit] Using project '${LIVEKIT_PROJECT}'"
lk project set-default "${LIVEKIT_PROJECT}" >/dev/null

cd "${SERVICE_DIR}"

LIVEKIT_TOML="${SERVICE_DIR}/livekit.${ENVIRONMENT}.toml"

if [[ "${ROTATE}" == "true" ]]; then
  if [[ ! -f "${LIVEKIT_TOML}" ]]; then
    echo "[livekit] ${LIVEKIT_TOML} not found; nothing to rotate. Run a create first." >&2
    exit 1
  fi

  AGENT_ID="$(awk -F'= ' '/id =/ {gsub(/"/, "", $2); print $2}' "${LIVEKIT_TOML}" | tr -d '[:space:]')"
  if [[ -z "${AGENT_ID}" ]]; then
    echo "[livekit] Unable to parse agent ID from ${LIVEKIT_TOML}" >&2
    exit 1
  fi

  echo "[livekit] Rotating agent ${AGENT_ID} in project ${LIVEKIT_PROJECT}..."
  yes | lk agent delete --id "${AGENT_ID}" >/dev/null

  "${SCRIPTS_DIR}/package-voice-agent-worker.sh" "${ENVIRONMENT}" create \
    --silent \
    --region "${LK_REGION}" \
    --secrets "APP_ENV=${ENVIRONMENT}"
else
  echo "[livekit] Deploying existing agent for ${ENVIRONMENT}..."
  "${SCRIPTS_DIR}/deploy-voice-agent-worker.sh" "${ENVIRONMENT}"
fi

echo "[livekit] Done."

