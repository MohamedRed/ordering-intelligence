# Onboarding service

Minimal service to support admin onboarding flows (e.g., menu flyer uploads).

## Endpoints
- `GET /healthz` – liveness probe
- `POST /uploads/menu-flyer` – multipart upload (`file` field). Stores in GCS bucket and returns `{ url, key, bucket }`.

## Environment
- `PORT` (default `8080`)
- `GCS_BUCKET` (default `ordering-intelligence-menus-dev`)
- `CORS_ORIGINS` (comma-separated, required; wildcard is rejected in staging/production)
- `PUBLIC_BASE_URL` (optional, override returned URL base). If unset, uses `https://storage.googleapis.com/<bucket>`.
- `MAKE_PUBLIC` (`true`|`false`, default `true`) – when true, uploaded files are made public.

## Local dev
```bash
cd backend/services/onboarding
npm install
npm run dev  # listens on 8080
```

To test upload:
```bash
curl -F file=@/path/to/menu.jpg http://localhost:8080/uploads/menu-flyer
```

## Deploy
Build via Dockerfile (Node 20). Cloud Run-compatible (listens on `$PORT`).
