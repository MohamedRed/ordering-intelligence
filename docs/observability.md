# Observability & Alerts

## Metrics
- Order service: `/metrics` (Prometheus exposition) + `/healthz/` (trailing slash)
- Notification service: `/metrics` + `/healthz`
- Voice agent worker (LiveKit): logs to stdout; smoke test script `backend/services/voice-agent-worker/scripts/livekit-smoke.sh`

## Alerting (Terraform)
- `infra/terraform/monitoring_alerts.tf` adds:
  - Uptime checks for order-service and notification-service (hosts configurable via `order_service_host`, `notification_service_host`).
  - Alert policy `uptime_critical` firing after 5m of failed checks.
  - Alert policy `push_failures` for `notifications_push_failed_total` > 5 over 5m (expects custom metric export of the Prom counters).
- Firestore TTL: `infra/terraform/firestore_ttl.tf` enables TTL on `expireAt` for `orders`, `alerts`, and `idempotency_keys`. Backends now set `expireAt` (orders/idempotency keys; alerts 14d in notification-service). Confirm TTL field appears in documents before applying.
- Wire notification channels by setting `alert_channel_ids` (email / PagerDuty / webhook IDs from Cloud Monitoring).

## Runbook sketches
- Order-service down: check Cloud Run/compute rollout, then Firestore/Env vars; check last deploy hash.
- Notification push failures: verify FCM server key, topic names, and Pub/Sub delivery; inspect `/alerts` for context.
- LiveKit smoke: run `backend/services/voice-agent-worker/scripts/livekit-smoke.sh` with `SIP_TRUNK` + `SIP_NUMBER` to validate hosted agent path without deploying.

## CI hooks
- `.github/workflows/terraform-ci.yml` already runs fmt/validate; monitor plan/apply manually.
- `.github/workflows/livekit-smoke.yml` (manual) invokes the smoke script; safe-guards skip when secrets are missing.
