# LiveKit Smoke Test (to reinstate)

## Goal
- Keep the LiveKit alternate path green. Run a daily/CI smoke test call to verify hosted agent + order flow.

## Sketch
- Script (pending) should:
  - Dial via LiveKit SIP test number to the hosted agent.
  - Send a short DTMF/voice flow to trigger `order_state.add_item` and `complete_order`.
  - Assert `get_order_state` RPC returns expected items.
  - End call; verify order-service received an order (optional mock).
- Use `lk sip participant create` or SIPp against LK inbound trunk.

## TODO
- Placeholder scripts exist at `tests/livekit_smoke.sh` and `backend/services/voice-agent-worker/scripts/livekit-smoke.sh`; implement SIPp or `lk sip participant create` flow.
- Wire into CI (nightly) and gate on staging LK project.
