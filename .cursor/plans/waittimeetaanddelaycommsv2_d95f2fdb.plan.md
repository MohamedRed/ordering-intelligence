---
name: WaitTimeETAAndDelayCommsV2
overview: Estimate voice ETA from historical created→ready times (daypart) using median when enough data, otherwise last-ready fallback, plus a business “notify delay” action via SMS/call with optional note.
todos:
  - id: order-lifecycle-timestamps
    content: "Order-service: persist confirmedAt/readyAt/completedAt/cancelledAt on first transition; include in orders-events."
    status: pending
  - id: wait-time-stats-service
    content: "Create wait-time-service: consume orders-events and maintain Firestore wait_time_stats per store/daypart with bounded samples + lastDurationMinutes."
    status: pending
    dependencies:
      - order-lifecycle-timestamps
  - id: store-default-wait-setting
    content: Add store setting for default_wait_minutes used when no history exists; expose in business settings UI.
    status: pending
  - id: eta-endpoint-and-agent-init
    content: Expose ETA endpoint/tool and fetch it in agent-webhooks conversation-init as dynamic variable eta_minutes.
    status: pending
    dependencies:
      - wait-time-stats-service
      - store-default-wait-setting
  - id: order-delay-comms-endpoint
    content: "Order-service: add POST /orders/{id}/customer-comms kind=delay and publish orders-events customer-comms message."
    status: pending
  - id: notification-delay-handler
    content: "Notification-service: handle order_customer_comms(kind=delay) and send SMS/call using existing logic; support optional note/template."
    status: pending
    dependencies:
      - order-delay-comms-endpoint
  - id: business-app-notify-delay-ui
    content: "Business app: add Notify delay action (channel + optional note) to order detail and call the new order-service endpoint."
    status: pending
    dependencies:
      - notification-delay-handler
---

# Voice ETA from historical prep times + “notify delay” action

## Goal

- **Voice agent ETA**: Quote an accurate “about N minutes” wait time using **historical created→ready durations**, computed per **store + daypart**.
- **Delay comms**: From the business app, allow a restaurant to send an **additional** SMS/AI call (“running late”) with an **optional note**, without changing order status.

## ETA definition + daypart

- **ETA boundary**: `createdAt → readyAt` (customer-facing total wait)
- **Granularity**: store + daypart
- `weekday_lunch`, `weekday_dinner`, `weekend_lunch`, `weekend_dinner`
- **Timezone**: use store timezone (or add a store setting if missing).

## Key discovery / constraint

`order-service` currently only persists `createdAt/updatedAt` and the *latest* `statusChange`. That is not enough to compute historical created→ready once an order moves past `ready`.

So we must **persist lifecycle timestamps** (at least `readyAt`) or maintain them in a durable stats system at transition time.

## Proposed solution

### 1) Persist lifecycle timestamps in `orders`

In `order-service`, add immutable timestamps recorded on first transition:

- `confirmedAt`
- `readyAt`
- `completedAt`
- `cancelledAt`

This unlocks analytics, SLA, and correct ETA.

**File**: [backend/services/order-service/cmd/order-service/main.go](backend/services/order-service/cmd/order-service/main.go)

### 2) Maintain rolling wait-time stats (per store/daypart)

Add a small service `wait-time-service` that consumes `orders-events` (Pub/Sub push + OIDC), and when an order first reaches `ready`:

- Compute `durationMinutes = round((readyAt - createdAt)/60s)`
- Bucket by `storeId + daypartKey`
- Update Firestore stats doc with:
- `count`
- `samples` = **bounded** list of recent durations (e.g. max 50) to allow median/p90 computation without complex quantile infra
- `lastDurationMinutes` (the newest sample)
- `updatedAt`

Firestore docs:

- `stores/{storeId}/wait_time_stats/{daypartKey}`

**Why store `samples`?**

- It lets us compute **median** when we have enough samples.
- It preserves **the last order duration** for low-data situations (your request).

### 3) ETA selection logic (includes “last order” fallback)

Let `defaultWaitMinutes` be a store setting (see next section).

For the current daypart bucket:

- If `samples.length == 0`: **ETA = defaultWaitMinutes**
- If `samples.length < MIN_SAMPLES_FOR_MEDIAN` (e.g. 10): **ETA = clamp(lastDurationMinutes, 3, 120)**
- Optional guardrail: also clamp to a sane band around default, e.g. `[defaultWaitMinutes/2, defaultWaitMinutes*2]`.
- Else (enough data): **ETA = round(median(samples))**

This matches what you want:

- **No data at all** → store default
- **A few orders** → use **last order** as the best signal
- **Enough history** → stable median per daypart

### 4) Store settings

Add to store doc:

- `order_comms.default_wait_minutes` (or `store.default_wait_minutes` if you prefer keeping comms separate)

This is the fallback ETA when there’s no usable history.

### 5) Expose ETA to the agent

Expose a lightweight ETA endpoint (pick one surface):

- **Option A (preferred)**: `agent-tools` tool `get_wait_time_estimate(storeId)`
- **Option B**: `order-service` `GET /stores/{storeId}/wait-time/estimate`

Then update `agent-webhooks` to fetch ETA at conversation-init and return it as:

- `dynamic_variables.eta_minutes`

So the agent can greet with: “It should take about {{eta_minutes}} minutes.”

## “Notify delay” (extra waiting) action

### UX

Add a new action in the business app order detail:

- **Notify delay**
- Channel: Auto / SMS / Call / None
- Optional note

### Backend

Do **not** overload status changes.

Add a new `order-service` endpoint:

- `POST /orders/{orderId}/customer-comms`
- body: `{ kind: 'delay', notifyMode, note, templateId? }`

Publish an `orders-events` message:

- `kind: 'order_customer_comms'`
- includes `tenantId`, `callerId`, `storeId`, and `comms.kind='delay'`

Update `notification-service` to handle this event and send SMS or ElevenLabs outbound call using existing plumbing.

## Files likely involved

- ETA timestamps + comms endpoint:
- [backend/services/order-service/cmd/order-service/main.go](backend/services/order-service/cmd/order-service/main.go)
- ETA stats service (new):
- `backend/services/wait-time-service/...`
- Agent init + tools:
- `backend/services/agent-webhooks/cmd/agent-webhooks/main.go`
- `backend/services/agent-tools/cmd/agent-tools/main.go`
- Delay notifications:
- [backend/services/notification-service/src/index.ts](backend/services/notification-service/src/index.ts)
- Business UI:
- [apps/business/lib/features/orders/order_detail_screen.dart](apps/business/lib/features/orders/order_detail_screen.dart)

## Acceptance criteria

- With **0** historical samples for a daypart, the agent uses **store default wait minutes**.
- With **1–9** samples, the agent uses the **most recent created→ready duration** (clamped).
- With **≥10** samples, the agent uses the **median** for that daypart.
- Business can send a **delay** SMS/call with an optional note, without changing status.