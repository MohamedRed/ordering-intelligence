# Menu Ingestion via Photos

Goal: let restaurants upload pictures of their menu and turn them into a structured, reviewable catalog with minimal effort and high safety.

## Pipeline Overview

1) **Capture/Upload**
   - Accept page-by-page menu photos through signed upload URLs.
   - Auto-reject blurry/low-resolution/tilted images (simple Laplacian blur + perspective heuristic).
   - Encourage page-by-page shots; allow multi-page uploads.

2) **Image Analysis**
   - Run Vertex Gemini image analysis against the uploaded page image.
   - Require strict JSON output and preserve enough job metadata to review the original upload alongside extracted rows.

3) **LLM Mapping (schema constrained)**
   - Input: uploaded page image and prompt guardrails.
   - Model prompt maps to strict schema: `id`, `name`, `category`, `price`, `currency`, `size/variant`, `allergens`, `available`.
   - Enforce enums/ranges in the prompt and require valid JSON; reject hallucinated items not visible on the uploaded menu.

4) **Validation**
   - Hard checks: required fields, price bounds (e.g., 0.5–200), duplicate IDs/names, currency consistency.
   - Confidence: if model confidence is weak or price is missing, flag for review.

5) **Human Review UI**
   - Side-by-side: image page on left, extracted rows on right.
   - Inline edits for name/price/category/size; accept/reject rows; set availability.
   - Approval publishes a versioned menu record; store original uploads + LLM draft + approved output.

6) **Publish**
   - Write approved items to the canonical menu store (Order Service/Firestore).
   - Trigger cache invalidation so voice agents pick up new items immediately.

## Data Shapes

### Menu item (LLM output → validator)
```json
{
  "id": "big_mac",
  "name": "Big Mac",
  "category": "burger",
  "price": 5.89,
  "currency": "USD",
  "sizes": [],
  "available": true,
  "allergens": ["gluten", "sesame"]
}
```

## Prompt Guardrails (LLM step)
- “Only use text visible in the uploaded menu image. Do not invent items or prices.”
- “Return strict JSON array of menu items; no prose.”
- “Price range 0.5–200; currency must be inferred from symbols or locale.”
- “If size/variant is unclear, leave sizes empty; do not guess.”
- “Reject rows if both name and price are missing.”

## Implemented (GCP stack)

- New Cloud Run service `backend/services/menu-ingestion`:
  - `POST /ingest/start` → signed URLs + jobId.
  - `POST /ingest/submit` → enqueue Pub/Sub task.
  - `GET /ingest/:jobId` → job status/draft pointer.
  - `POST /ingest/:jobId/approve` → publish to Firestore menus.
  - `/tasks/process` (Pub/Sub push) → Vertex AI Gemini image analysis → validation → Firestore draft.
- Auth/CORS: all endpoints except `/health` require bearer auth. Admin calls use Firebase ID tokens; Pub/Sub/Scheduler/CI use allowlisted Google OIDC ID tokens. Staging/prod reject wildcard CORS origins at startup.
- Data stores: Firestore (`menus_ingest`, `menus_drafts`, `restaurants/{id}/menus`), GCS bucket for uploads.
- Compute: Cloud Run + Pub/Sub push; image analysis and mapping via Vertex Gemini.
- Config: `MENU_BUCKET`, `MENU_INGEST_TOPIC`, `VERTEX_PROJECT`, `VERTEX_LOCATION`, `GOOGLE_CLOUD_PROJECT`.
- **Order-service sync:** On approve, the service now also upserts a canonical menu document into the `menus` collection (storeId doc) matching order-service schema so `/stores/{storeId}/menu/snapshot` stays in sync.
- Admin UI: set `MENU_INGESTION_BASE_URL` (Dart define) in the admin app to point at the per-env Cloud Run URL.
- Pub/Sub fan-out: optional `MENU_UPDATES_TOPIC` (`PUBSUB_TOPIC_MENU_UPDATES`) will receive a message `{storeId, updatedAt, jobId, source}` on approval for downstream cache busting/agents.
- Cost guards (defaults): process max 5 pages, 40 items/page, 120 items total per job (`MENU_MAX_PAGES`, `MENU_MAX_ITEMS_PER_PAGE`, `MENU_MAX_TOTAL_ITEMS`). Increase cautiously; Gemini 3 image calls are the main cost driver.
- Loop guard: jobs are marked `processedAt`; push handler skips reprocessing unless a `processing` job exceeds its 30m window, then it can be retried once. This prevents Pub/Sub redeliveries from re-running the same job endlessly.
- Stuck-job cleanup: endpoint `/tasks/cleanup` resets expired `processing` jobs to `queued` (schedule via Cloud Scheduler hourly).

### IAM / Permissions
- The menu-ingestion service account uses explicit least-privilege project roles for Firestore, Pub/Sub publishing, Vertex AI, logging, monitoring, and trace writing.
- Menu upload object access is scoped to the menu ingestion bucket with bucket-level Storage Object Admin rather than a project-wide editor grant.

Admin app wiring
- The Admin Flutter app exposes `/menu-ingestion` for ops review. It lists ingestion jobs, loads the draft with original uploads and composite previews, shows extracted items with thumbnails, and approves drafts through `POST /ingest/:jobId/approve`.
- New uploads are still initiated from the onboarding wizard, which stores menu flyers and triggers `/onboarding-sessions/:id/ingest-menu`; `/menu-ingestion` is the queue/review/publish surface for generated drafts.

### Automated test
- Added `tests/e2e/scripts/menu_ingestion_flow.ts` with npm script `npm run menu:ingest --prefix tests/e2e`. It runs the full flow: start → upload sample image → submit → poll → read draft → approve → verify Firestore publish. Required envs: `MENU_INGESTION_BASE_URL`, `MENU_INGESTION_RESTAURANT_ID`, `MENU_INGESTION_SAMPLE_PATH`, and `GOOGLE_CLOUD_PROJECT`.

## Why direct multimodal analysis
- Simpler production IAM: the service only needs Vertex AI plus scoped storage, Firestore, and Pub/Sub permissions.
- Lower pipeline complexity: no separate OCR service or OCR-specific permission model is required.
- Reviewability: original uploads, extracted rows, generated composites, and approval state are stored for audit.

## Safety & Compliance
- Keep original uploads + extracted draft data for audit trails.
- Record who approved and when (versioned menus).
- Add price/availability sanity gates to prevent wrong charges.

## Rollout Plan
1) Keep validator and review UI coverage current with the production API.
2) Keep Order Service write-path and voice-agent cache invalidation covered by integration tests.
3) Add per-tenant storage/billing limits and GCS lifecycle policies (e.g., 30–90 days).
4) Expand with allergen detection and multi-language menus as needed.
