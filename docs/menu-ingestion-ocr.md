# Menu Ingestion via Photos/PDFs

Goal: let restaurants upload pictures/PDFs of their menu and turn them into a structured, reviewable catalog with minimal effort and high safety.

## Pipeline Overview

1) **Capture/Upload**
   - Accept JPEG/PNG/PDF.
   - Auto-reject blurry/low-resolution/tilted images (simple Laplacian blur + perspective heuristic).
   - Encourage page-by-page shots; allow multi-page uploads.

2) **OCR + Layout**
   - Run an OCR engine that returns text + bounding boxes (e.g., PaddleOCR/DocTR/Tesseract). Keep raw text + coordinates.
   - Group into lines/columns using geometric clustering; preserve heading hierarchy when present.

3) **LLM Mapping (schema constrained)**
   - Input: JSON of OCR blocks (text, box, page, column group).
   - Model prompt maps to strict schema: `id`, `name`, `category`, `price`, `currency`, `size/variant`, `allergens`, `available`.
   - Enforce enums/ranges in the prompt and require valid JSON; reject hallucinated items not present in OCR text.

4) **Validation**
   - Hard checks: required fields, price bounds (e.g., 0.5–200), duplicate IDs/names, currency consistency.
   - Confidence: if OCR/LLM confidence < threshold or price is missing, flag for review.

5) **Human Review UI**
   - Side-by-side: image/PDF page on left, extracted rows on right.
   - Inline edits for name/price/category/size; accept/reject rows; set availability.
   - Approval publishes a versioned menu record; store raw OCR + LLM draft + approved output.

6) **Publish**
   - Write approved items to the canonical menu store (Order Service/Firestore).
   - Trigger cache invalidation so voice agents pick up new items immediately.

## Data Shapes

### OCR block (input to LLM)
```json
{
  "page": 1,
  "text": "Big Mac®",
  "box": [x0, y0, x1, y1],
  "line": 12,
  "column": 1
}
```

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
- “Only use text present in OCR blocks. Do not invent items or prices.”
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
  - `/tasks/process` (Pub/Sub push) → Vision OCR → Vertex AI Gemini mapping → validation → Firestore draft.
- Data stores: Firestore (`menus_ingest`, `menus_drafts`, `restaurants/{id}/menus`), GCS bucket for uploads.
- Compute: Cloud Run + Pub/Sub push; OCR via Cloud Vision; LLM via Vertex Gemini 1.5 Flash.
- Config: `MENU_BUCKET`, `MENU_INGEST_TOPIC`, `VERTEX_PROJECT`, `VERTEX_LOCATION`, `GOOGLE_CLOUD_PROJECT`.
- **Order-service sync:** On approve, the service now also upserts a canonical menu document into the `menus` collection (storeId doc) matching order-service schema so `/stores/{storeId}/menu/snapshot` stays in sync.
- Admin UI: set `MENU_INGESTION_BASE_URL` (Dart define) in the admin app to point at the per-env Cloud Run URL.
- Pub/Sub fan-out: optional `MENU_UPDATES_TOPIC` (`PUBSUB_TOPIC_MENU_UPDATES`) will receive a message `{storeId, updatedAt, jobId, source}` on approval for downstream cache busting/agents.
- Cost guards (defaults): process max 5 pages, 40 items/page, 120 items total per job (`MENU_MAX_PAGES`, `MENU_MAX_ITEMS_PER_PAGE`, `MENU_MAX_TOTAL_ITEMS`). Increase cautiously; Gemini 3 image calls are the main cost driver.
- Loop guard: jobs are marked `processedAt`; push handler skips reprocessing unless a `processing` job exceeds its 30m window, then it can be retried once. This prevents Pub/Sub redeliveries from re-running the same job endlessly.
- Stuck-job cleanup: endpoint `/tasks/cleanup` resets expired `processing` jobs to `queued` (schedule via Cloud Scheduler hourly).

### IAM / Permissions
- The menu-ingestion service account currently uses `roles/editor` plus `roles/storage.objectAdmin`, `roles/pubsub.publisher`, `roles/aiplatform.user`, logging/monitoring/trace writers.
- Rationale: legacy `roles/cloudvision.user` is not provisioned by IAM and custom roles cannot include `vision.images.annotate`. `roles/editor` is the smallest predefined role that consistently allows Vision OCR calls; tighten later once Google exposes a dedicated Vision role.

Next UI step: Admin review page (not yet implemented) to show image + extracted rows for approval.

Admin app wiring
- A placeholder screen lives at `/menu-ingestion` in the Admin Flutter app; hook it to the API endpoints above and render the draft items side-by-side with the uploaded image. Use the `menus_drafts/{jobId}` doc (Firestore) to drive the view; approval should call `POST /ingest/:jobId/approve`.

### Automated test
- Added `tests/e2e/scripts/menu_ingestion_flow.ts` with npm script `npm run menu:ingest --prefix tests/e2e`. It runs the full flow: start → upload sample image → submit → poll → read draft → approve → verify Firestore publish. Required envs: `MENU_INGESTION_BASE_URL`, `MENU_INGESTION_RESTAURANT_ID`, `MENU_INGESTION_SAMPLE_PATH`, and `GOOGLE_CLOUD_PROJECT`.

## Why hybrid (OCR + LLM) instead of pure multimodal
- Auditability: raw text + boxes are stored and reviewable.
- Cost/latency: OCR is cheap; LLM sees compact JSON, not pixels.
- Determinism: you can re-run mapping with new prompts without re-uploading images.

## Safety & Compliance
- Keep original uploads + OCR text for audit trails.
- Record who approved and when (versioned menus).
- Add price/availability sanity gates to prevent wrong charges.

## Rollout Plan
1) Prototype locally with PaddleOCR + one LLM (gpt-4o-mini or similar) and the schema above.
2) Add validator + minimal review UI; gate publishing on approval.
3) Integrate Order Service write-path; add cache invalidation for voice agent menus.
4) Add per-tenant storage/billing limits and S3/GCS lifecycle (e.g., 30–90 days).
5) Expand with allergen detection and multi-language menus as needed.
