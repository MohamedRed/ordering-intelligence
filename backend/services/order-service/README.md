# Order Service

Go microservice responsible for menu management, order validation, persistence, and integrations with downstream systems (POS, notifications).

## Capabilities (Planned)

- Order intake endpoint invoked by the conversation orchestrator (implemented).
- Retrieval of stored orders by ID.
- Event emission to Pub/Sub for downstream analytics/notifications.
- (Planned) CRUD APIs for menus, categories, items, and modifiers.
- (Planned) Inventory and availability checks using tenant configuration.
- (Planned) POS connector framework for pushing orders into external systems.

## Local Development

```bash
go run ./cmd/order-service
```

Environment variables:

- `PORT`
- `FIRESTORE_PROJECT_ID`
- `GOOGLE_APPLICATION_CREDENTIALS`
- `PUBSUB_TOPIC_ORDERS`
