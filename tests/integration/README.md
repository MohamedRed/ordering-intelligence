# Integration Smoke Tests

This smoke suite validates that the web apps load and that the dev channel-gateway
health endpoint is reachable. It is designed to run in CI against the dev
environment + test tenant.

## Required env vars
- `CONSUMER_APP_URL`
- `BUSINESS_APP_URL`
- `DRIVER_APP_URL`
- `ADMIN_APP_URL`
- `CHANNEL_GATEWAY_BASE_URL` (optional; enables `/healthz` check)

## Run locally
```bash
node tests/integration/smoke.mjs
```
