# Voice Agent Worker Deployment Plan (LiveKit – alternate path)

## Overview

LiveKit hosted agents are **not the current production path** (we use ElevenLabs hosted agents today), but the LiveKit worker is kept as a cost/control fallback. The instructions below stay valid for when we choose to switch.

Key responsibilities remain the same:

1. Load the correct preset JSON from `infra/voice-agents/<env>.json`.
2. Apply `location_code` overrides supplied via dispatch metadata or fallback env vars.
3. Maintain the LiveKit session, including the OpenAI Realtime bridge, until the call ends.
4. Expose in-call order state (tools + RPC `get_order_state`) and broadcast a checkout data packet when the order is completed.
5. Fetch a menu snapshot from the Order Service (if `ORDER_SERVICE_URL`/`STAGING_ORDER_SERVICE_URL`/`PROD_ORDER_SERVICE_URL` is set) and append it to the system prompt for grounding and validation.

## Prerequisites

1. Install the latest [LiveKit CLI](https://docs.livekit.io/home/cli/).
2. Authenticate and set the default project:
   ```bash
   lk cloud auth
   lk project set-default "<project-name>"
   ```
3. Create `backend/services/voice-agent-worker/livekit.toml` by copying the provided template and
   populate it after running `lk agent create` once. The resulting file is gitignored.
4. Ensure `infra/secrets/.env` contains `OPENAI_API_KEY` (and any other provider keys) for the target
   environment.
5. Set inbound routing vars per environment:
   - `TELEPHONY_PROVIDER` = `us-livekit-pstn` (US LiveKit number) or `sip-trunk` (carrier DID)
   - `TELEPHONY_NUMBER` = E.164 of the LiveKit number or carrier DID
   - `TELEPHONY_DISPATCH_RULE_ID` = LiveKit dispatch rule ID that should receive the call

## One-time agent registration

For a new environment:

```bash
cd backend/services/voice-agent-worker
lk agent create --secrets OPENAI_API_KEY=sk-xxx --secrets APP_ENV=staging
```

This command assigns an agent ID, writes it to `livekit.toml`, and triggers the initial build. Future
deployments reuse the same agent ID.

## Deploying to LiveKit Cloud

CI and local operators can call the orchestration script to deploy or rotate agents:

```bash
# Deploy the existing staging agent
./scripts/livekit-agent-apply.sh staging

# Rotate the dev agent (delete + recreate)
./scripts/livekit-agent-apply.sh dev --rotate
```

Under the hood the helper wraps `scripts/package-voice-agent-worker.sh`, which copies
`backend/services/voice-agent-worker`, `backend/libs/voice-agent-config`, and `infra/voice-agents`
into a temporary directory before running `lk agent ...`. The script deletes the temporary context on
success and writes the resulting `livekit.toml` back to `backend/services/voice-agent-worker/livekit.<env>.toml`.

> ⚠️ **Plan limits:** the LiveKit Cloud free tier allows only one hosted agent per project. If
> you need separate dev/staging/prod agents, upgrade the project or re-use the same agent across
environments.

### Free-tier rotation workflow

When running with a single hosted slot, invoke:

```bash
./scripts/livekit-agent-apply.sh staging --rotate
```

The command deletes the current agent, recreates it in the supplied project, and refreshes
`livekit.<env>.toml`. Repeat for the next environment to swap back. Document the active environment in
release notes or runbooks so QA/ops know which project currently hosts the worker.


## Operational notes

- **Explicit dispatch** – Dispatch rules must include `"agentName": "oi-voice-agent"` (or your
  override) so calls always resolve to the correct hosted worker.
- **Room cleanup** – The worker calls `RoomServiceClient.deleteRoom` during shutdown. Look for the
  `voice-agent-worker:cleanup` log in LiveKit Cloud after synthetic calls to confirm cleanup.
- **Monitoring** – Use `lk agent status` and `lk agent logs --log-type deploy` to observe rollout
  progress. The LiveKit Cloud dashboard also shows replica counts and recent errors.
- **Config updates** – Re-run the deployment whenever presets change so the baked image includes the
  latest JSON. Avoid storing secrets in the image; inject everything via LiveKit Cloud secrets.
- **Metadata automation** – Continue using `npm run --prefix tests/e2e sip:update-metadata` and
  `voice:set-profile` to keep dispatch metadata and Firestore voice profiles aligned.
