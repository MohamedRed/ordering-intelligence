# ElevenLabs voice menu consumption guide

This repo’s `agent-tools` menu snapshot endpoint returns a **voice-optimized** payload intended for ElevenLabs/ConvAI agents.

## What the tool returns
When your agent calls:

- `GET /v1/stores/{storeId}/menu/snapshot`

it receives a payload that includes:

- `spokenMenuFr`: **pre-written French script** (30–60s) designed to be spoken naturally.
- `suggestedFlowFr`: short next-step prompts to keep the dialogue interactive.
- `categories[]`: grouped items with:
  - `priceDisplay`: e.g. `8,50 €`
  - `priceSpeechFr`: e.g. `huit euros cinquante`

## How the agent should use it (recommended)
In your ElevenLabs agent instructions (system prompt / tool usage guidance):

- Always **speak `spokenMenuFr`** when presenting the menu.
- If the user asks to browse or compare, use `categories` to list options.
- When speaking a price, always use **`priceSpeechFr`** (never `priceCents`).
- Do not read technical fields (IDs, cents, JSON keys) to the user.

## Why this matters (French numbers)
Many voice models mispronounce numeric formats (especially in French). The tool provides `priceSpeechFr` so the agent can speak prices reliably.

## Call-start personalization (recommended)
Your `agent-webhooks` conversation-init webhook can provide **dynamic variables** that let the agent greet returning callers and offer quick reorders.

### Dynamic variables you can expect
- `customerName`: known name from previous orders (may be empty)
- `isReturningCustomer`: boolean
- `topReorders`: array of up to 3 “last distinct orders” for this store (may be missing/empty)
- `callerId`: caller phone number (E.164-ish)
- `callSid`: Twilio call SID

### How the agent should use them
- If `isReturningCustomer` and `customerName` is present:
  - Greet personally: “Bonjour {customerName} …”
- If `topReorders[0]` exists:
  - Offer it early: “Voulez-vous reprendre {topReorders[0].title} ?”
- If `topReorders` is empty/missing:
  - Proceed with normal flow (don’t mention personalization at all).

### Important: include identity fields when creating an order
When calling the order creation tool, include the conversation identity fields so the backend can update the customer profile/reorders:
- `tenantId` (from dynamic variables)
- `storeId` (from dynamic variables)
- `callerId` (from dynamic variables)
- `callSid` (from dynamic variables)
- `customerName` (if confirmed/known)

This is what enables “welcome back” and reorder suggestions on future calls.


