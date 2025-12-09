# End-to-End Testing Plan

These scenarios validate the ordering flow across LiveKit SIP ingress, the hosted voice agent, and downstream fulfillment services.

## Synthetic Call Flow
- `scripts/synthetic_call.ts` can run in two modes:
  - **Dry run (default):** validates configuration and prints next steps without invoking external services.
  - **Live run:** initiates a Twilio call, optionally generates a LiveKit token, and polls Firestore for an order document (when `--require-order`).
- Configure environment variables before a live run:
  - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_CALL_FROM`, `TWILIO_CALL_TO`, `TWILIO_TWIML_URL`
  - `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (optional)
  - `FIRESTORE_PROJECT_ID`, `FIRESTORE_ORDER_COLLECTION` (default `orders`)
- Run: `npm install && npm test -- --dry-run` (default). Set `DRY_RUN=false` to execute against real services.

## SIP Dispatch Validation
- `npm run sip:validate` checks that:
  - The inbound trunk ID in `LIVEKIT_SIP_INBOUND_TRUNK_ID` exists and (optionally) contains `LIVEKIT_SIP_EXPECTED_NUMBERS`.
  - The dispatch rule ID in `LIVEKIT_SIP_DISPATCH_RULE_ID` is linked to the trunk and enforces the expected pin (if supplied).
  - When `LIVEKIT_SIP_HEALTH_RUN_CALL=true`, the script uses the outbound trunk to place a synthetic call (with optional DTMF) and logs the resulting SIP participant identifiers.
- US vs non-US routing: set `TELEPHONY_PROVIDER=us-livekit-pstn` with `TELEPHONY_NUMBER=<LiveKit US number>` to make the health call target the first-party LiveKit number. Otherwise keep `TELEPHONY_PROVIDER=sip-trunk` and set `LIVEKIT_SIP_HEALTH_CALL_TO` to your carrier DID.
- Required env vars (typically sourced from `infra/secrets/.env`):
  - `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
  - `LIVEKIT_SIP_INBOUND_TRUNK_ID`, `LIVEKIT_SIP_DISPATCH_RULE_ID`
  - `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`, `LIVEKIT_SIP_HEALTH_CALL_TO`, `LIVEKIT_SIP_HEALTH_ROOM`
  - optional: `LIVEKIT_SIP_EXPECTED_NUMBERS`, `LIVEKIT_SIP_EXPECTED_PIN`, `LIVEKIT_SIP_HEALTH_DTMF`
- SIPp scenarios under `tests/e2e/scripts/sipp/scenarios/` still provide load/stress validation when needed.
- Workflow `.github/workflows/sip-health.yml` runs this script nightly for dev/staging/prod (see repo secrets list below).

## Business App Regression
- Flutter integration tests covering sign-in, drawer navigation, order list rendering using golden snapshots.

## Admin Console Regression
- Flutter driver tests verifying dashboard metrics rendering and alert feed updates using mock backend responses.

> Current status: synthetic call runner executes in dry-run mode in CI; provide credentials to exercise a full Twilio/LiveKit/Firestore flow.
