# Menu Grounding for Voice Agents

## Overview
- Order service exposes `GET /stores/{storeId}/menu/snapshot` returning a compact menu snapshot (items, prices, updated timestamp).
- Intended for ElevenLabs or LiveKit agents to ground prompts/tools.

## Snapshot format
```
{
  "storeId": "demo-store",
  "updated": "2025-12-08T12:00:00Z",
  "items": [
    {"id": "pizza-margherita", "name": "Margherita", "priceCents": 1200, "available": true, "category": "pizza", "modifiers": [], "description": ""}
  ]
}
```

## Agent wiring (implemented)
- ElevenLabs: run `python elevenlabs/scripts/apply_menu_snapshot.py` (uses `ORDER_SERVICE_URL` + `STORE_ID`) to inject the latest snapshot between `<!-- MENU_SNAPSHOT_START/END -->` markers in `agent_configs/Order-taker.json` (or override `AGENT_CONFIGS`). Idempotent; rerun after menu changes before pushing the agent.
- LiveKit worker: fetches `${ORDER_SERVICE_URL}/stores/{storeId}/menu/snapshot` on room join and appends it to the system prompt; script `backend/services/voice-agent-worker/scripts/fetch-menu.sh` fetches the snapshot for debugging.

## Script
- `backend/services/order-service/scripts/export_menu_snapshot.sh` downloads a snapshot for a store for manual inspection or uploading to agents.

## Future
- Add ETag/If-None-Match to reduce traffic.
- Categories now present in menu items; modifiers remain a flat list.
