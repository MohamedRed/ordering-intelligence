# LiveKit SIP Smoke (detailed steps - not yet scripted)

1) Prereqs
   - lk CLI authenticated.
   - Staging LK project with inbound trunk.
   - Test DID/SIP number routed to staging trunk.
   - Agent preset deployed (hosted) to staging.

2) Arrange dispatch metadata
   - Ensure dispatch rule maps calls to the hosted agent and sets room name/prefix.

3) Call flow (SIPp)
   - Use SIPp to place a call to the trunk URI.
   - Play simple audio or DTMF to trigger `order_state.add_item` tool.
   - Assert data packet `show_checkout` is seen (TBD via LK logs or agent RPC).

4) Simplified lk CLI flow
   - `lk sip participant create --trunk-id ... --from ... --to ... --room-name smoke --participant-identity smoke`
   - Observe hosted agent logs for session start/stop.

5) Pass criteria
   - Call connects and ends cleanly.
   - Agent responds and order tool is invoked at least once.
   - No 5xx in LK logs.

6) CI hook
   - Run daily in staging; export results to Slack/email.

7) Menu freshness for agent tests
   - Set `ORDER_SERVICE_URL` and `STORE_ID` for the target environment.
   - If `menu-updates` Pub/Sub is available, set `MENU_UPDATES_SUBSCRIPTION` on the worker (pull sub on the `menu-updates` topic) so the agent refreshes menus automatically between smokes.

Status: scripts still placeholder (`tests/livekit_smoke.sh`, `backend/services/voice-agent-worker/scripts/livekit-smoke.sh`).
