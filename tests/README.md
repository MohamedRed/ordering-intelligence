# Automated Testing Strategy

The synthetic call runner gives us a manual verification path, but we still
need automated coverage to guard deployments. This document outlines the plan
for Phase 2.

## Current Coverage
- `tests/e2e/scripts/synthetic_call.ts` exercises the LiveKit SIP trunk, hosted voice agent, and order service with live Twilio + LiveKit calls.
- GitHub Actions workflow `e2e-ci.yml` runs the script in dry-run mode to catch
  regressions in tooling.
- GitHub Actions workflow `sip-health.yml` runs nightly against dev/staging/prod trunks using `npm run sip:validate`.
- `tests/integration/smoke.mjs` performs smoke checks for the deployed web apps and channel-gateway healthz in CI.
- `tests/integration/ui_flow.mjs` runs Playwright-based UI flows against deployed web apps in CI.

## Utility Scripts
- `npm run --prefix tests/e2e sip:update-metadata -- --location-code fr-paris` updates the metadata JSON on the LiveKit dispatch rule so every SIP job carries the correct `voiceProfile.location_code`.
- `npm run --prefix tests/e2e voice:set-profile -- --document-id store_123 --location-code fr-paris --preset-id preset_dev` patches the Firestore `voice_profile` block for a store to keep runtime overrides in sync with operations.

## Near-Term Additions
1. **Service Unit Tests**
   - Order service: request validation, price calculations, Pub/Sub publishing.
   - Notification service: handoff webhook validation and fan-out.
   - Voice agent config library: preset loading, location overrides, tool schema validation.
   - Target frameworks: Go test, Jest (Node), vitest (agents library).

2. **Contract & Integration Tests**
   - JSON schema validation for Pub/Sub events (`backend/libs/shared/config/schema`).
   - Mocked Twilio webhook replay using signed fixtures.
   - Firestore emulator test harness exercised via GitHub Actions matrix.

3. **Continuous Synthetic Calls**
   - Staging workflow that runs the Twilio call hourly with cost guardrails.
   - Alert on failure via Slack/PagerDuty.

4. **LiveKit SIP Regression Coverage**
   - Nightly job runs `npm run sip:validate -- --run-call` (see `tests/e2e/scripts/validate_dispatch.ts`) using the env vars defined in `infra/secrets/.env`. This verifies the inbound trunk + dispatch rule exist and optionally places a synthetic call through the outbound trunk.
   - SIPp scenarios run against staging trunks to stress concurrent inbound calls (baseline: 10 concurrent calls, P95 < 1.2 s for Call Connect).
   - Twilio `<Dial><Sip>` synthetic call runner validates the connection policy + secure trunking (TLS/SRTP) configuration after every Terraform apply.
   - Failures page `#telephony-alerts` and automatically attach trunk ID, dispatch rule ID, and agent ID for debugging.

5. **Performance Budgets**
   - Track LiveKit SIP dispatch latency and voice agent turn/response timing.
   - Baseline order service HTTP latency (P95 < 1.5 s) before prod promotions.

## Tooling Backlog
- Add `tests/package.json` workspace with lint/test scripts.
- Provision shared test utilities under `backend/libs/shared/testing`.
- Store secrets for CI in GitHub OIDC -> Secret Manager for ephemeral tokens.

Owners: QA Engineering + Service teams. Track progress under Phase 2 “Automated
testing” milestone in `docs/implementation-roadmap.md`.
