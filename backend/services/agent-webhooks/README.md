# agent-webhooks

Small runtime service for voice agent webhooks (e.g. ElevenLabs conversation init).

This service is intentionally **decoupled from onboarding state**. It routes inbound webhook requests
by looking up a durable Firestore mapping in `phone_number_routes`.

## Endpoints

- `GET /healthz`
- `POST /elevenlabs/conversation-init`

## Config

Environment variables (same conventions as other Go services in this repo):

- `PORT` (default: `8086`)
- `ENVIRONMENT`
- `FIRESTORE_PROJECT_ID` (**required**)
- `GOOGLE_APPLICATION_CREDENTIALS` (optional)

Webhook auth:

- `ELEVENLABS_CONVERSATION_INIT_SECRET` (optional)
  - If set, request must include header `x-elevenlabs-conversation-init-secret`
    (or legacy `x-onboarding-webhook-secret`) with the same value.

## Firestore

Reads:

- `phone_number_routes/elpn_<elevenlabs_phone_number_id>`
- `phone_number_routes/to_<e164_without_plus>`


