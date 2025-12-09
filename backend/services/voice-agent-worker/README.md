# Voice Agent Worker (LiveKit alternate path)

LiveKit agent worker that loads preset definitions from `infra/voice-agents/*.json`, applies
location-specific overrides, and boots an OpenAI Realtime session using the LiveKit Agents SDK.
Production currently uses ElevenLabs hosted agents; keep this worker for future switchbacks when we want more control/cost efficiency.

### Menu grounding
- Fetch the store snapshot: `./scripts/fetch-menu.sh` (uses ORDER_SERVICE_URL + STORE_ID envs).
- Include the JSON snapshot in the agent prompt or pre-load into tool context.

## Running locally

```bash
cd backend/services/voice-agent-worker
cp .env.example .env   # optional
npm install
npm run start
```

Environment variables:

| Variable | Description |
| --- | --- |
| `APP_ENV` | `dev`, `staging`, or `prod`. Defaults to `dev`. |
| `VOICE_AGENT_LOCATION_CODE` | Optional override for the store’s `voice_profile.location_code`. |
| `VOICE_AGENT_CONFIG_DIR` | Optional path to an alternate preset directory. Defaults to `infra/voice-agents`. |
| `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` | Standard LiveKit worker credentials consumed indirectly by `@livekit/agents`. |
| `OPENAI_API_KEY` | Required by `@livekit/agents-plugin-openai` when `llm.provider` is `openai`. |

### In-call order state & RPCs

- The worker now keeps a lightweight in-memory order state so UI clients can poll it.
- Built-in tools exposed to the LLM:
  - `order_state.add_item(name, price?, details?)`
  - `order_state.list_items()`
  - `order_state.remove_items(orderIds: string[])`
  - `order_state.complete_order()` (broadcasts a `show_checkout` data packet with total)
- RPCs registered on room join:
  - `get_order_state` → `{ success, data: { items, total_price, item_count } }`

These complement the existing HTTP tools loaded from `infra/voice-agents/*.json`; no backend changes are required to try the new flow.

### Menu grounding

- On startup the worker fetches a menu snapshot from `${ORDER_SERVICE_URL}/stores/${STORE_ID}/menu/snapshot`
  (or `STAGING_ORDER_SERVICE_URL` / `PROD_ORDER_SERVICE_URL`) when available.
- The snapshot is appended to the system prompt so the LLM sees current item IDs, categories, modifiers, and prices.
- Built-in `order_state.add_item` validates items against the menu when present and rejects unknown entries.

At runtime the worker receives `ctx.data.voiceProfile.location_code` (if supplied by the orchestrator).
If absent, it falls back to the environment variable and finally to the baseline preset.

## Deployment

### LiveKit Cloud (hosted agents)

The worker now deploys directly to LiveKit Cloud. Use the helper script to stage a clean build
context and invoke the `lk agent` CLI. Typical commands:

```bash
# Deploy an existing hosted agent (rebuild image + rollout)
./scripts/package-voice-agent-worker.sh dev deploy --secrets APP_ENV=dev

# Create a new agent and capture its ID in livekit.<env>.toml
./scripts/package-voice-agent-worker.sh staging create --silent --region us-east --secrets APP_ENV=staging
```

The script copies the worker sources, shared config library, and preset JSON into a temporary
directory, runs the requested `lk agent` subcommand, then writes the resulting `livekit.toml`
back to `backend/services/voice-agent-worker/livekit.<env>.toml`.

### Rotating a single hosted slot

On the LiveKit Cloud free tier, only one agent may be active per project. To switch the hosted
agent between environments, delete the current agent and recreate it for the next environment:

```bash
lk project set-default ordering-intelligence-dev
lk agent delete --id CA_existingAgentId
./scripts/package-voice-agent-worker.sh staging create --silent --region us-east --secrets APP_ENV=staging
```

Repeat the process to switch back to dev. Each environment keeps its config in
`livekit.<env>.toml`, so recreation is idempotent.

### Observability

- `lk agent status` shows replica counts, rollout health, and resource usage.
- `lk agent logs --log-type deploy` streams worker logs from LiveKit Cloud.

See `docs/voice-agent-worker-deployment.md` for deeper operational guidance and dispatch metadata
expectations.
