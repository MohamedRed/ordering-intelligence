# LiveKit Smoke Test

## Goal
- Keep the LiveKit alternate path green. Run a daily/CI smoke test call to verify hosted agent + order flow.

## Current Scripted Coverage
- `tests/livekit_smoke.sh` delegates to `npm run --prefix tests/e2e sip:validate`.
- It validates LiveKit credentials, optional inbound trunk and dispatch rule IDs, expected numbers, and expected dispatch pins.
- Set `LIVEKIT_SMOKE_RUN_CALL=true` to place a LiveKit outbound SIP health call through `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`.
- Set `LIVEKIT_SMOKE_STRICT=1` in CI or release checks so missing LiveKit smoke configuration fails instead of being skipped for local development.

## Remaining Extensions
- Add a scripted DTMF/voice flow that triggers `order_state.add_item` and `complete_order`.
- Verify order-service received the expected order after the SIP participant completes.
- Keep SIPp scenarios for load/regression against staging trunks.
