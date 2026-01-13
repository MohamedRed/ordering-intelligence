---
name: Omni+GroupOrders
overview: Extend the omni-channel ordering agent with first-class group orders that support single payer or split pay (including delivery), leveraging existing Stripe Connect onboarding and keeping store ops to a single kitchen ticket.
todos:
  - id: group-order-domain
    content: Implement GroupOrderSession in order-service (Firestore collection + endpoints) and tag order items with participant metadata; group order finalizes into one store-facing order.
    status: completed
  - id: payments-service-stripe-checkout
    content: Create payments-service to generate Stripe Checkout sessions (single payer or split) using tenant Stripe Connect account, consume webhooks, and mark group orders paid/submitted.
    status: completed
    dependencies:
      - group-order-domain
  - id: agent-tools-group-order-tools
    content: Expose group order tools via agent-tools (proxy endpoints) so ElevenLabs agent can create/join/add/checkout group orders.
    status: completed
    dependencies:
      - group-order-domain
      - payments-service-stripe-checkout
  - id: comms-group-order-updates
    content: Send join links, payment links, reminders, and order status updates to host/participants (WhatsApp via Meta fallback, Telegram, etc.) via notification-service.
    status: completed
    dependencies:
      - payments-service-stripe-checkout
  - id: alloc-rules-hardening
    content: Define deterministic allocation rules for delivery fee/tip/discounts + rounding; persist allocation snapshot for audit and support refunds.
    status: completed
    dependencies:
      - group-order-domain
  - id: snap-telegram-join-flows
    content: Implement Telegram and Snap Lens join + payment link surfacing (share code/link UX).
    status: completed
    dependencies:
      - agent-tools-group-order-tools
      - comms-group-order-updates
---

# Omni-channel Agent + Group Orders (single payer or split pay)

## Recommendation (product + ops)

- Model group ordering as a **shared cart session** that becomes **one store-facing order** (single kitchen ticket) with items tagged by participant.
- Support both:
- **One payer**: host pays the full amount.
- **Split pay**: each participant pays their calculated share.
- Allow split pay for delivery, with one delivery address and a deterministic fee allocation.

## Core design

### Entities (Firestore)

- `group_orders/{groupOrderId}`
- `tenantId`, `storeId`, `fulfillmentType`, `delivery` (if any)
- `status`: `open|locked|payment_pending|paid|submitted|expired|cancelled`
- `host`: `channelContact`
- `participants[]`: `{participantId, channelContact, displayName}`
- `items[]`: existing `orderItem` shape + `participantId` (and optional `participantLabel` for kitchen)
- `pricing`: computed totals + allocation metadata
- `paymentMode`: `single_payer|split_by_participant`
- `expiresAt`
- `group_orders/{groupOrderId}/payments/{paymentId}`
- `payerParticipantId`, `amountCents`, `currency`
- `provider`: `stripe`
- `stripeCheckoutSessionId` (or `paymentIntentId`)
- `status`: `requires_payment|succeeded|failed|refunded|expired`

### Allocation (defaults)

- **Each participant pays for their own items** (items they added).
- **Shared fees** (delivery fee, platform fee, discounts): allocate **pro-rata by participant subtotal**, with remainder cents assigned to host for deterministic rounding.
- **Tip**: default to **per-payer tip** (each Checkout session can include tip), optionally also support “host tip only”.

### Checkout + payment

- Reuse existing tenant Stripe Connect onboarding (`tenants/{tenantId}.stripe_account_id` is already written by onboarding).
- Implement split pay using **one Stripe Checkout session per payer**:
- On webhook `checkout.session.completed`, mark that payer as paid.
- When all payers paid, atomically create a single `orderRecord` in order-service and mark `group_orders/{id}.status=submitted`.

### Omni-channel implications

- Group order join is channel-agnostic: participants join via a **share code/link**.
- WhatsApp: agent sends join + pay links via WhatsApp text (Meta Cloud API fallback for proactive outbound text).
- Telegram: bot can handle join/pay links.
- Snap Lenses: lens can display the join code and launch pay link in browser.

## Services/components

- **Order domain**: extend `order-service` to support group order session lifecycle (create/join/add/lock/finalize) while keeping a single order write path.
- **Payments**: add a dedicated `payments-service` (Node/TS preferred to reuse existing Stripe tooling patterns in `onboarding`) that:
- creates Checkout sessions (single payer or split)
- handles Stripe webhooks
- updates `group_orders/.../payments/...` statuses
- triggers final order creation when fully paid
- **Agent tooling**: extend `agent-tools` with proxy endpoints/tools for:
- `group_order_create`, `group_order_join`, `group_order_add_items`, `group_order_checkout`, `group_order_status`
- **Outbound comms**: extend `notification-service` routing to send group-order payment links + status updates.

## Key files/directories (expected)

- [`backend/services/order-service/cmd/order-service/main.go`](backend/services/order-service/cmd/order-service/main.go) (will be refactored into smaller files as we add group order endpoints)
- [`backend/services/agent-tools/cmd/agent-tools/main.go`](backend/services/agent-tools/cmd/agent-tools/main.go)
- [`backend/services/notification-service/src/index.ts`](backend/services/notification-service/src/index.ts)
- [`backend/services/onboarding/src/index.ts`](backend/services/onboarding/src/index.ts) (reference only: Stripe Connect account provisioning)
- `backend/services/payments-service/...` (new)
- Terraform wiring under `infrastructure/terraform/environments/*` to deploy `payments-service` and configure secrets
- `common_error.md` (append Stripe/webhook + idempotency notes as we encounter issues)