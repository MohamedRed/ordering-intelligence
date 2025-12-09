#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="${ROOT_DIR}/backend/services/voice-agent-worker"
ENV_FILE="${ROOT_DIR}/infra/secrets/.env"
LIVEKIT_TOML="${SERVICE_DIR}/livekit.toml"

if ! command -v lk >/dev/null 2>&1; then
  echo "[deploy] The LiveKit CLI (lk) is not installed. Install it via https://docs.livekit.io/home/cli/ before proceeding." >&2
  exit 1
fi

if [[ ! -f "${LIVEKIT_TOML}" ]]; then
  echo "[deploy] Missing ${LIVEKIT_TOML}. Copy livekit.toml.template and run 'lk agent create' once to register the agent." >&2
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

cd "${SERVICE_DIR}"

declare -a secrets
secrets+=("APP_ENV=${ENVIRONMENT}")

if [[ -n "${VOICE_AGENT_LOCATION_CODE_OVERRIDE:-}" ]]; then
  secrets+=("VOICE_AGENT_LOCATION_CODE=${VOICE_AGENT_LOCATION_CODE_OVERRIDE}")
fi

if [[ ${#secrets[@]} -gt 0 ]]; then
  echo "[deploy] Synchronising LiveKit Cloud secrets..."
  secret_args=()
  for secret in "${secrets[@]}"; do
    secret_args+=(--secrets "${secret}")
  done
  lk agent update "${secret_args[@]}"
fi

echo "[deploy] Deploying voice-agent-worker to LiveKit Cloud..."
lk agent deploy

echo "[deploy] Deployment complete. Use 'lk agent status' to monitor the rollout."
