#!/usr/bin/env bash
set -euo pipefail

# Placeholder: verify required env vars for Pub/Sub push subscription deployment.

: "${NOTIFICATION_SERVICE_PUSH_ENDPOINT:?set NOTIFICATION_SERVICE_PUSH_ENDPOINT}"
: "${NOTIFICATION_SERVICE_SA_EMAIL:?set NOTIFICATION_SERVICE_SA_EMAIL}"
: "${PROJECT_ID:?set PROJECT_ID}"

echo "Pub/Sub envs present. (Deployment not executed.)"
