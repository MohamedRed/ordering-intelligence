# Pub/Sub push hardening audit

Last updated: 2026-06-19T09:02:02Z

## Scope

This audit tracks backend endpoints that consume Google Pub/Sub push envelopes or equivalent event push callbacks for the Ordering Intelligence platform. The production gate is:

- malformed, non-retryable payloads are acknowledged with a 2xx response and logged with a reason;
- processable events that fail because of downstream infrastructure keep a retryable 5xx response;
- authenticated push endpoints fail closed in staging/production when OIDC audience or service-account allowlist configuration is missing;
- valid Pub/Sub/OIDC callers must present a Google ID token with the expected audience and an allowlisted service-account email.

## Handled endpoints and evidence

### delivery-service `/tasks/orders-events`

Status: handled in this branch.

Evidence:

- `backend/services/delivery-service/cmd/delivery-service/main.go`
  - `serviceConfig.OrdersEventsAllowedEmails` loads `ORDERS_EVENTS_OIDC_ALLOWED_EMAILS`.
  - `handleOrdersEvents` now requires both `ORDERS_EVENTS_OIDC_AUDIENCE` and `ORDERS_EVENTS_OIDC_ALLOWED_EMAILS` whenever `RequireAuth` is true.
  - missing OIDC config returns `500 {"error":"pubsub_push_auth_misconfigured"}` instead of accepting unauthenticated Pub/Sub push traffic.
  - missing or invalid bearer tokens return `401`.
  - verified ID-token email must match the allowlist.
- `backend/services/delivery-service/cmd/delivery-service/auth_config.go`
  - staging/production startup rejects missing orders-events Pub/Sub OIDC audience/allowlist while auth is enabled.
- Regression tests:
  - `TestLoadConfigIncludesOrdersEventsOIDCAllowlist`
  - `TestLoadConfigRejectsMissingOrdersEventsOIDCInProduction`
  - `TestHandleOrdersEventsFailsClosedWhenOIDCAllowlistMissing`
  - `TestHandleOrdersEventsRequiresBearerWhenOIDCHardened`
  - existing malformed Pub/Sub envelope ACK test remains green.
- Local validation:
  - `/tmp/go/bin/go test ./...` in `backend/services/delivery-service` passed.

### notification-service `/events/orders`, `/events/dispatch`, `/events/deliveries`

Status: handled before this audit update; re-verified by source inspection.

Evidence:

- `backend/services/notification-service/src/index.ts`
  - each event route calls `requireGoogleOidcRequest` before decoding the Pub/Sub push envelope.
  - routes use per-audience config (`ORDERS_EVENTS_OIDC_AUDIENCE`, `DISPATCH_EVENTS_OIDC_AUDIENCE`, `DELIVERIES_EVENTS_OIDC_AUDIENCE`) and shared service-account allowlist (`EVENTS_OIDC_ALLOWED_EMAILS`).
- `backend/services/notification-service/src/internal_auth.ts`
  - fails closed when audience or allowlist is missing.
  - validates Google ID token audience.
  - rejects emails outside the allowlist.
- Regression tests:
  - `backend/services/notification-service/tests/internal_auth.test.ts`
  - `backend/services/notification-service/tests/orders_events.test.ts`
  - `backend/services/notification-service/tests/pubsub_envelope.test.ts`

### dispatch-service `/tasks/orders-events`

Status: handled before this audit update; re-verified by source inspection.

Evidence:

- `backend/services/dispatch-service/cmd/dispatch-service/main.go`
  - route invokes `requireDispatchTaskAuth` before processing orders-events payloads.
- `backend/services/dispatch-service/cmd/dispatch-service/task_auth.go`
  - requires `ORDERS_EVENTS_OIDC_AUDIENCE` and `ORDERS_EVENTS_OIDC_ALLOWED_EMAILS` when auth is enabled.
  - validates Google ID token audience and allowlisted email.
  - staging/production cannot disable dispatch auth.
- Regression tests exist in `config_test.go` and `pubsub_push_test.go` for config and malformed push ACK behavior.

### recommendation-service, customer-profile-service, wait-time-service `/tasks/orders-events`

Status: handled in earlier hardening commits on this branch.

Evidence:

- Recent branch history includes:
  - `0c678c10 Ack malformed recommendation order events`
  - earlier companion hardening for customer-profile and wait-time services in the same audit pass.
- Each service now has `pubsub_push.go` decode helpers and `pubsub_push_test.go` malformed-envelope coverage.
- Prior local validation recorded for those services: `go test ./...`, `go vet ./...`, and `staticcheck ./...` passed.

### typesense-indexer Eventarc/Firestore callback

Status: handled in earlier hardening commit on this branch.

Evidence:

- Recent branch history includes `a8821aad fix: ack malformed typesense events`.
- `backend/services/typesense-indexer/cmd/typesense-indexer/event_ack_test.go` covers:
  - invalid CloudEvent JSON is acknowledged with `200` and reason `invalid_event`;
  - invalid Firestore payload is acknowledged with `200` and reason `invalid_firestore_event`;
  - missing Firestore document path is acknowledged with `204`;
  - real processable-event infrastructure failures remain retryable with `500`.

## Deferred items

No Pub/Sub push hardening item is deferred in this audit update.

Separate CI runner/workflow note: switching `.github/workflows/web-integration-smoke.yml` from self-hosted labels to GitHub-hosted `ubuntu-latest` is still blocked from this session because the current GitHub token has `repo` scope but not `workflow` scope. That is a CI runner routing blocker, not a Pub/Sub push hardening deferral.
