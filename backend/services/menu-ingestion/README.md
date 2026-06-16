# Menu Ingestion Service (GCP)

Turns menu photos/PDFs into structured items with OCR + Vertex AI, with human review.

## Flow
- `POST /ingest/start` → returns signed URLs for uploads + jobId.
- Client uploads images/PDF pages to signed URLs.
- `POST /ingest/submit` with `jobId` → publishes Pub/Sub task.
- `/tasks/process` (Pub/Sub push) downloads files from GCS, runs Vision OCR, maps to menu items via Vertex Gemini, stores draft in Firestore.
- `GET /ingest/:jobId` → job status.
- `POST /ingest/:jobId/approve` → writes approved items to `restaurants/{restaurantId}/menus/*` in Firestore.

All ingest lifecycle endpoints except `/health` require a bearer token. Browser/admin
calls use Firebase ID tokens; Pub/Sub, Cloud Scheduler, and internal CI/ops calls use
Google OIDC ID tokens when `ALLOW_GOOGLE_ID_TOKENS=true`.

## GCP Resources
- **Storage bucket** for uploads (env: `MENU_BUCKET` or `STORAGE_BUCKET_MENUS`).
- **Pub/Sub topic** for processing (env: `MENU_INGEST_TOPIC` or `PUBSUB_TOPIC_MENU_INGEST`).
- **Firestore** (native mode) collections: `menus_ingest`, `menus_drafts`, `restaurants/{id}/menus`.
- **Vision API** for OCR.
- **Vertex AI** (Gemini 1.5 Flash) for schema mapping.

## Required env vars
```
MENU_BUCKET=oi-menus-dev
MENU_INGEST_TOPIC=menu-ingest
VERTEX_PROJECT=<gcp-project>
VERTEX_LOCATION=us-central1
GOOGLE_CLOUD_PROJECT=<gcp-project>
MENU_INGESTION_CORS_ORIGINS=https://admin.example.com
ALLOW_GOOGLE_ID_TOKENS=true
GOOGLE_ID_TOKEN_AUDIENCES=https://menu-ingestion.example.com
GOOGLE_ID_TOKEN_ALLOWED_EMAILS=menu-ingestion@PROJECT_ID.iam.gserviceaccount.com
RENDER_TIMEOUT_MS=60000   # optional; defaults to 60s per image generation
```

- Image generation uses Vertex AI via the service account (no API key). Ensure the service account has `roles/aiplatform.user`.
- Staging and production must set explicit CORS origins; wildcard origins are rejected at startup.
- Pub/Sub push subscriptions and Cloud Scheduler jobs should set their OIDC audience to `GOOGLE_ID_TOKEN_AUDIENCES`.

Optional overrides: `STORAGE_BUCKET_MENUS`, `PUBSUB_TOPIC_MENU_INGEST`, `ORDER_SERVICE_URL` if you want to push final menus downstream later.

## Local dev
```
cd backend/services/menu-ingestion
npm install
npm run dev
```

## Deployment (Cloud Run)
```
gcloud run deploy menu-ingestion \
  --source . \
  --region us-central1 \
  --set-env-vars MENU_BUCKET=oi-menus-dev,MENU_INGEST_TOPIC=menu-ingest,VERTEX_PROJECT=$PROJECT_ID,VERTEX_LOCATION=us-central1 \
  --set-secrets GOOGLE_CLOUD_API_KEY=genai-api-key:latest
```
Configure Pub/Sub push subscription to hit `/tasks/process` with an OIDC token.

## Notes
- OCR is capped to first 400 lines for prompt size; adjust in `buildLlmPrompt` if needed.
- Price sanity: 0.5–200 enforced. Unknown items or missing names will fail validation.
- All drafts remain in `menus_drafts` with raw OCR lines for audit.
