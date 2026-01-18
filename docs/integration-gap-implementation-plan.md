# Integration Gaps – Full Implementation Plan

This document captures the remaining integration-testing gaps and the planned implementation to close them in the dev environment. All test-only hooks are dev‑only, internal‑auth gated, and written to be safe, deterministic, and modular.

## Goals

- Cover remaining critical user flows in CI (no local runs required).
- Avoid external provider dependency where possible (use safe test hooks).
- Keep implementation modular and small‑file friendly.
- Codify infra changes in Terraform for repeatability.

## Remaining Gaps & Plan

### 1) Channel OAuth flows (Telegram / Discord / Snapchat)

**Gap**: CI cannot execute real OAuth handshakes.

**Plan**
- Add internal, dev‑only test endpoints in `channel-gateway` to create synthetic channel sessions per provider.
- Sessions should mirror production shape: `channel`, `account_id`, `user_id`, `auth_provider`, `display_name`, `store_id`, timestamps.
- Reuse `channel_sessions` collection; no new schema.

**CI Test**
- Create simulated session for each provider.
- Call `/.../identity?sessionId=...` and assert customer resolution is present.

**Terraform**
- Add internal auth audience for channel‑gateway (if needed).
- Allow `github-ci` service account in internal allowlist.

---

### 2) Menu ingestion end‑to‑end (Pub/Sub → menu‑ingestion → menu updates)

**Gap**: Only ingestion status is patched; no pipeline coverage.

**Plan**
- Add internal `menu-ingestion` test hook that:
  - Accepts `{ jobId, restaurantId, menu }`.
  - Writes expected final menu output documents.
  - Publishes a `menu-updates` event in the same format as production.
- Reuse existing ingestion job created by `/onboarding-sessions/:id/ingest-menu`.

**CI Test**
- Start ingestion via onboarding service.
- Call menu‑ingestion test hook with a minimal menu payload.
- Verify order‑service `/menu` returns the new menu.

**Terraform**
- Internal auth audience for menu‑ingestion.
- Allow `github-ci` SA in allowlist.

---

### 3) Stripe webhook signature path

**Gap**: We simulate webhook without real signature verification.

**Plan**
- Add a CI test that signs a `payment_intent.succeeded` event with the real dev webhook secret.
- POST to `/webhooks/stripe` (real endpoint).

**CI Test**
- Generate signature (Stripe webhook signing format).
- Assert 200 response and payment record updated in Firestore.

**Terraform**
- Already wired: `STRIPE_WEBHOOK_SECRET` is in Secret Manager.

---

### 4) Notifications delivery (push/SMS/email)

**Gap**: We hit event endpoints, but do not verify provider delivery.

**Plan**
- Add `NOTIFICATIONS_DRY_RUN=true` in dev notification-service:
  - Skip external provider calls.
  - Record counters (in Firestore or in-memory + debug endpoint).
- Add internal endpoint to read delivery counters in tests.

**CI Test**
- Send orders/dispatch/deliveries events.
- Assert counters incremented for each channel.

**Terraform**
- Set `NOTIFICATIONS_DRY_RUN` env var for dev.
- Allow internal access for the counters endpoint.

---

### 5) Driver routing + stop lifecycle

**Gap**: No coverage for route optimization or stop status updates.

**Plan**
- Seed a route document for a store with stops.
- Call:
  - `/v1/stores/{storeId}/routes/optimize`
  - `/v1/stores/{storeId}/routes/{routeId}/stops/{deliveryId}/status`
- Verify dispatch/order updates are emitted.

**CI Test**
- Optimize route with 2+ locations.
- Update stop status and confirm lifecycle event.

---

### 6) Voice / telephony handoff

**Gap**: Twilio + ElevenLabs flows not tested.

**Plan**
- Add internal test endpoint in notification-service or agent‑webhooks to simulate call handoff:
  - Accept `callSid`, `storeId`, `agentId`.
  - Create transcript + trigger handoff logic.

**CI Test**
- Call simulate endpoint.
- Verify transcript + handoff state written.

---

## Execution Order

1) Channel OAuth simulation
2) Menu ingestion test hook
3) Signed Stripe webhook test
4) Notifications dry‑run + counters
5) Driver route lifecycle
6) Voice/telephony simulation
7) Wire CI + Terraform + run workflow

## CI Workflow Updates

- Add new tests to `.github/workflows/web-integration-smoke.yml` after existing ones.
- Add any new env vars needed (notification base URL, dry‑run flag, etc).

## Terraform Updates (dev)

- Internal auth audiences for any new test endpoints.
- Allow `github-ci` SA in service allowlists.
- Add `NOTIFICATIONS_DRY_RUN=true` for notification-service.

## Success Criteria

- All tests pass in `Web Integration Smoke` for dev env.
- No production‑side effects (dev‑only hooks + internal auth).
- Deterministic behavior for CI.
