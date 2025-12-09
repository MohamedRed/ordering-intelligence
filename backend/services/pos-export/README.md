# POS Export Service (Scaffolding)

This Cloud Run service exposes a manual export endpoint that proxies the
Order Service and returns CSV payloads that can be imported into external POS
systems. The initial implementation focuses on scaffolding so we can iterate on
API contracts with early pilot partners.

## Endpoints

`GET /exports/orders?storeId=<id>`  
Proxies the Order Service `/exports/orders` endpoint and returns a CSV body.
Future work:
- AuthN/AuthZ (signed URLs or API keys).
- Date range & status filters.
- Direct POS push handlers.

`GET /healthz`  
Basic service health probe.

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ORDER_SERVICE_URL` | ✅ | — | Base URL for the order service (e.g. `https://order-service-<project>.run.app`). |
| `ENVIRONMENT` | ❌ | `dev` | Identifier used for logging & health output. |
| `PORT` | ❌ | `8080` | HTTP port. |

## Development

```bash
cd backend/services/pos-export
npm install
npm run dev
```

## Tests

```bash
npm test
```

## Deployment

Add this service to the infrastructure Terraform once the endpoint contract is
finalised. The Dockerfile targets Cloud Run (`node:20-alpine` base).
