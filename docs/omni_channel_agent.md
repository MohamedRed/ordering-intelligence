# Omni-channel Agent

This document describes the omni-channel messaging layer that routes Telegram/Snap Lens (and future channels) into the existing ElevenLabs agent + tool stack, and enables outbound channel updates via `orders-events`.

## Services

### channel-gateway (Go)

Inbound channel adapter + ElevenLabs conversation forwarding. Stores session mappings in Firestore.

**Endpoints**

- `GET /healthz`
- `POST /telegram/webhook/{accountId}`
- `POST /snap/lens/session/start`
- `POST /snap/lens/store/select`
- `POST /snap/lens/cart/update`
- `POST /snap/lens/voice/turn`

**Environment**

- `FIRESTORE_PROJECT_ID` (required)
- `ELEVENLABS_API_KEY` (required for WebSocket signed URL)
- `ELEVENLABS_API_BASE_URL` (default `https://api.elevenlabs.io`)
- `ELEVENLABS_DEFAULT_AGENT_ID` (fallback agent id)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_WEBHOOK_SECRET`
- `TELEGRAM_WEBAPP_URL` (base WebApp URL for inline group-order results)
- `SESSION_IDLE_MINUTES` (default `20`)
- `CUSTOMER_PROFILE_SERVICE_URL` (optional, for dynamic vars)
- `RECOMMENDATION_SERVICE_URL` (optional, for dynamic vars)
- `WAIT_TIME_SERVICE_URL` (optional, for dynamic vars)

**Firestore**

- `channel_routes/{channel}_{accountId}`
  - `channel`, `account_id`, `tenant_id`, `store_id`, `business_type`, `elevenlabs_agent_id`
- `channel_sessions/{channel}_{accountId}_{userId}`
  - `elevenlabs_conversation_id`, `tenant_id`, `store_id`, `last_seen_at`, `thread_id`, etc.

### channel-comms (Node)

Outbound order status updates (future marketing scaffolding).

**Endpoint**

- `POST /events/orders` (Pub/Sub push target)

**Environment**

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_API_BASE_URL` (optional)

## ElevenLabs Conversation Flow

`channel-gateway` uses the ElevenLabs WebSocket API:

1) `GET /v1/convai/conversation/get-signed-url?agent_id=...&include_conversation_id=true`
2) Dial the signed WebSocket URL.
3) Send `conversation_initiation_client_data` with `dynamic_variables`.
4) Send `user_message` for the inbound text.
5) Read `agent_response` and return text to the channel.

Sessions keep the WebSocket open per channel user (in-memory). Conversations restart if the instance is recycled.

## Order Contact Metadata

`order-service` now accepts an optional `channelContact` object. If present, it is stored on the order record and propagated to `orders-events` for outbound updates.

Example:

```json
{
  "channelContact": {
    "channel": "telegram",
    "accountId": "bot_123",
    "userId": "987654321",
    "threadId": "12",
    "displayName": "Alex",
    "locale": "en"
  }
}
```

## Snap Lens JSON Protocol

All endpoints accept JSON and return JSON.

- `POST /snap/lens/session/start`
  - Request: `{ "accountId", "userId", "storeId?", "displayName?", "locale?" }`
  - Response: `{ "sessionId", "storeId", "tenantId", "businessType", "agentId" }`

- `POST /snap/lens/store/select`
  - Request: `{ "sessionId", "storeId" }`

- `POST /snap/lens/cart/update`
  - Request: `{ "sessionId", "cart" }`

- `POST /snap/lens/voice/turn`
  - Request: `{ "sessionId", "text" }`
  - Response: `{ "text", "conversationId" }`

## Routing Notes

- Voice calls use `phone_number_routes` / `agent_routes` (handled by `agent-webhooks`).
- Channel adapters use `channel_routes` (handled by `channel-gateway`).
- Dynamic variables are computed by the shared `agent-context` library.
