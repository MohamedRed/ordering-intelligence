#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: package-voice-agent-worker.sh <environment> [lk-agent-subcommand ...]

Creates a temporary build context containing only the files required to build
and deploy the voice-agent worker with the LiveKit CLI. Optionally executes an
`lk agent` command (create/deploy/update/etc.) using that build context.

Examples:
  # Create a new agent for dev (prompts for region unless --region provided)
  ./scripts/package-voice-agent-worker.sh dev create --silent --region us-east --secrets APP_ENV=dev

  # Deploy an existing staging agent
  ./scripts/package-voice-agent-worker.sh staging deploy --secrets APP_ENV=staging
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

ENVIRONMENT="$1"
shift

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oi-voice-agent-${ENVIRONMENT}-XXXX")"
cleanup() { rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT

SRC_WORKER_DIR="${ROOT_DIR}/backend/services/voice-agent-worker"
SRC_LIB_DIR="${ROOT_DIR}/backend/libs/voice-agent-config"
SRC_INFRA_DIR="${ROOT_DIR}/infra/voice-agents"
CONFIG_SOURCE="${SRC_WORKER_DIR}/livekit.${ENVIRONMENT}.toml"
CONFIG_TARGET="${SRC_WORKER_DIR}/livekit.${ENVIRONMENT}.toml"

mkdir -p "${TEMP_DIR}/backend/services" "${TEMP_DIR}/backend/libs" "${TEMP_DIR}/infra"

rsync -a --exclude 'node_modules' --exclude 'dist' "${SRC_WORKER_DIR}/" "${TEMP_DIR}/backend/services/voice-agent-worker/"
rsync -a --exclude 'node_modules' --exclude 'dist' "${SRC_LIB_DIR}/" "${TEMP_DIR}/backend/libs/voice-agent-config/"
rsync -a "${SRC_INFRA_DIR}/" "${TEMP_DIR}/infra/voice-agents/"
cp "${SRC_WORKER_DIR}/Dockerfile" "${TEMP_DIR}/Dockerfile"
cp "${SRC_WORKER_DIR}/package.json" "${TEMP_DIR}/package.json"
if [[ -f "${SRC_WORKER_DIR}/package-lock.json" ]]; then
  cp "${SRC_WORKER_DIR}/package-lock.json" "${TEMP_DIR}/package-lock.json"
fi

if [[ -f "${SRC_WORKER_DIR}/.dockerignore" ]]; then
  cp "${SRC_WORKER_DIR}/.dockerignore" "${TEMP_DIR}/.dockerignore"
else
  cat <<'EOF' > "${TEMP_DIR}/.dockerignore"
node_modules
dist
.git
EOF
fi

if [[ -f "${CONFIG_SOURCE}" ]]; then
  cp "${CONFIG_SOURCE}" "${TEMP_DIR}/livekit.toml"
fi

if [[ $# -gt 0 ]]; then
  echo "[package] Running: lk agent $* ${TEMP_DIR}" >&2
  set +e
  lk agent "$@" "${TEMP_DIR}"
  status=$?
  set -e
  if [[ ${status} -eq 0 && -f "${TEMP_DIR}/livekit.toml" ]]; then
    cp "${TEMP_DIR}/livekit.toml" "${CONFIG_TARGET}"
    echo "[package] Updated ${CONFIG_TARGET}" >&2
  else
    echo "[package] Command failed; build context was ${TEMP_DIR}" >&2
    exit ${status}
  fi
fi
