#!/usr/bin/env bash
set -euo pipefail

# LiveKit SIP smoke wrapper.
# Delegates to tests/e2e/scripts/validate_dispatch.ts so manual smoke runs,
# scheduled SIP health checks, and CI use the same validation logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
E2E_DIR="${REPO_ROOT}/tests/e2e"

strict="${LIVEKIT_SMOKE_STRICT:-0}"
install_deps="${LIVEKIT_SMOKE_INSTALL_DEPS:-0}"

missing=()
for name in LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET; do
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  message="Missing LiveKit smoke env: ${missing[*]}"
  if [ "$strict" = "1" ]; then
    echo "$message" >&2
    exit 2
  fi
  echo "$message; skipping smoke. Set LIVEKIT_SMOKE_STRICT=1 to fail instead."
  exit 0
fi

if [ -n "${SIP_TRUNK:-}" ] && [ -z "${LIVEKIT_SIP_OUTBOUND_TRUNK_ID:-}" ]; then
  export LIVEKIT_SIP_OUTBOUND_TRUNK_ID="$SIP_TRUNK"
fi

if [ -n "${SIP_NUMBER:-}" ] && [ -z "${LIVEKIT_SIP_HEALTH_CALL_TO:-}" ]; then
  export LIVEKIT_SIP_HEALTH_CALL_TO="$SIP_NUMBER"
fi

if [ -n "${ROOM_NAME:-}" ] && [ -z "${LIVEKIT_SIP_HEALTH_ROOM:-}" ]; then
  export LIVEKIT_SIP_HEALTH_ROOM="$ROOM_NAME"
fi

if [ -n "${PARTICIPANT_NAME:-}" ] &&
  [ -z "${LIVEKIT_SIP_HEALTH_PARTICIPANT_NAME:-}" ]; then
  export LIVEKIT_SIP_HEALTH_PARTICIPANT_NAME="$PARTICIPANT_NAME"
fi

export LIVEKIT_SIP_HEALTH_ROOM="${LIVEKIT_SIP_HEALTH_ROOM:-sip-smoke-$(date +%Y%m%d%H%M%S)}"
export LIVEKIT_SIP_HEALTH_IDENTITY_PREFIX="${LIVEKIT_SIP_HEALTH_IDENTITY_PREFIX:-sip-smoke}"
export LIVEKIT_SIP_HEALTH_RUN_CALL="${LIVEKIT_SIP_HEALTH_RUN_CALL:-${LIVEKIT_SMOKE_RUN_CALL:-false}}"
export LIVEKIT_SIP_HEALTH_TIMEOUT="${LIVEKIT_SIP_HEALTH_TIMEOUT:-60000}"

if [ "$LIVEKIT_SIP_HEALTH_RUN_CALL" = "true" ] ||
  [ "$LIVEKIT_SIP_HEALTH_RUN_CALL" = "1" ]; then
  call_missing=()
  [ -z "${LIVEKIT_SIP_OUTBOUND_TRUNK_ID:-}" ] && call_missing+=("LIVEKIT_SIP_OUTBOUND_TRUNK_ID")
  if [ "${TELEPHONY_PROVIDER:-sip-trunk}" = "us-livekit-pstn" ]; then
    [ -z "${TELEPHONY_NUMBER:-}" ] && call_missing+=("TELEPHONY_NUMBER")
  else
    [ -z "${LIVEKIT_SIP_HEALTH_CALL_TO:-}" ] && call_missing+=("LIVEKIT_SIP_HEALTH_CALL_TO")
  fi
  if [ "${#call_missing[@]}" -gt 0 ]; then
    echo "Missing LiveKit health-call env: ${call_missing[*]}" >&2
    exit 2
  fi
fi

if [ ! -d "${E2E_DIR}/node_modules" ]; then
  if [ "$install_deps" = "1" ]; then
    npm ci --prefix "$E2E_DIR"
  else
    echo "Missing ${E2E_DIR}/node_modules. Run npm ci --prefix tests/e2e or set LIVEKIT_SMOKE_INSTALL_DEPS=1." >&2
    exit 2
  fi
fi

npm run --prefix "$E2E_DIR" sip:validate -- "$@"
