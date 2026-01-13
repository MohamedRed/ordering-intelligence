---
name: IngestionSplitForDemo
overview: Split admin onboarding ingestion into Fast menu-only and optional slow image enrichment steps, without rewriting the ingestion pipeline; keep voice demo workable after Step 2 only.
todos:
  - id: extend-ingestion-types
    content: Extend menu-ingestion types to include modifierGroups and bundleRules; update order-service-sync types accordingly.
    status: pending
  - id: update-analysis-prompts
    content: Update ingestion prompts in ingestion.ts (vertex + agent fallback) to extract richer raw fields (sizes/options/combos) while remaining menu-only.
    status: pending
    dependencies:
      - extend-ingestion-types
  - id: add-normalization-step
    content: Add a stage-B Gemini JSON prompt that converts extracted items into validated modifierGroups and bundleRules (combo builder), with strict post-validation to prevent hallucinated references.
    status: pending
    dependencies:
      - update-analysis-prompts
  - id: split-onboarding-steps
    content: "Admin app: add a new onboarding step for Image Enrichment; Step 2 becomes FastIngestion and is demo-ready after completion."
    status: pending
  - id: onboarding-fast-and-resume-api
    content: "Onboarding-service: support ingest-menu mode=menu_only and a resume-images endpoint to restart the same job in full mode."
    status: pending
    dependencies:
      - split-onboarding-steps
  - id: menu-ingestion-fast-mode
    content: "Menu-ingestion tasks: support per-job pipelineMode menu_only vs full and resumeRequestedAt to bypass processed/ready skip logic safely."
    status: pending
    dependencies:
      - onboarding-fast-and-resume-api
  - id: update-order-service-sync
    content: Update mapDraftItemsToOrderServiceMenu to emit modifierGroups and bundleRules to order-service; apply size requiredness rule when multiple sizes exist.
    status: pending
    dependencies:
      - add-normalization-step
  - id: dev-verification
    content: "Dev-only verification: run fast ingestion and confirm publish+snapshot works; then run resume-images and confirm images are enriched without changing item IDs."
    status: pending
    dependencies:
      - menu-ingestion-fast-mode
      - update-order-service-sync
---

# Admin onboarding: split menu ingestion into Fast + Image Enrichment

## Goal

Enable a **voice-agent demo** after only:

- **Step 1**: Upload menu pages + business info
- **Step 2 (Fast)**: Extract a structured, voice-ready menu (no thumbnails/photos)

…and move the slow **Gemini image model** work into a later step:

- **Step 3 (Slow, optional)**: Generate/assign thumbnails/photos to the already-extracted menu items

You confirmed the desired step structure is:

- **Menu → FastIngestion → ImageEnrichment → Agent → Stripe → Finalize**

## Key discovery (current code)

- The ingestion pipeline is already stage-based in `menu-ingestion`:
  - `analyze → composites → extract → assign → write` in [backend/services/menu-ingestion/src/routes/tasks.ts](backend/services/menu-ingestion/src/routes/tasks.ts)
- **The slow part** is primarily `composites/extract/assign` using `gemini-3-pro-image-preview` (`COMPOSITE_MODEL`) from [backend/services/menu-ingestion/src/config.ts](backend/services/menu-ingestion/src/config.ts)
- Admin UI already polls ingestion via onboarding-service (`sync-ingest`) and maps menu-ingestion `ready` → `succeeded`, so **fast completion can be treated as “done” for demo**.

## Proposed behavior

### Step 2 (FastIngestion)

- Trigger an ingestion job that runs only:
  - **Analyze** menu pages (Gemini text model: `ANALYSIS_MODEL`)
  - **(Still include the prompt-v2 normalization step)** to produce `modifierGroups`/`bundleRules` (text-only)
  - **Write** `menus_drafts/{jobId}` with items (no imageUrl/photoUrl)
  - Mark job `status=ready`, `progressStage=done`

### Step 3 (ImageEnrichment)

- Resume the **same jobId** and run only:
  - `composites → extract → assign → write`
- Critical: **reuse the draft items created in Step 2 as the canonical menu** and only enrich `imageUrl/photoUrl`.
  - This avoids re-extraction drift between Step 2 and Step 3.

### Demo flow

- Demos stop at Step 2. Step 3 is never entered.

## API / data-flow (high level)

```mermaid
flowchart TD
  AdminUI -->|Step1Upload| OnboardingSvc
  AdminUI -->|Step2TriggerFast| OnboardingSvc
  OnboardingSvc -->|CreateJob(mode=menu_only)| Firestore
  OnboardingSvc -->|Publish(jobId)| PubSub
  PubSub -->|/tasks/process| MenuIngestionSvc
  MenuIngestionSvc -->|WriteDraft(menu_only)| Firestore

  AdminUI -->|Step3ResumeImages| OnboardingSvc
  OnboardingSvc -->|UpdateJob(mode=full,resume=true)| Firestore
  OnboardingSvc -->|Publish(jobId)| PubSub
  PubSub -->|/tasks/process| MenuIngestionSvc
  MenuIngestionSvc -->|EnrichDraftWithImages| Firestore
```

## Implementation outline

### 1) Admin app: add a new onboarding step

Update [apps/admin/lib/features/onboarding/onboarding_screen.dart](apps/admin/lib/features/onboarding/onboarding_screen.dart):

- Add a new step constant (e.g. `_stepImages = 2`) and shift later steps
- Update `_stepCount`, labels in `_stepIndicator()`
- Split current ingestion UI into two screens:
  - **FastIngestion step**: existing ingestion controls + “Publish menu” + “Verify snapshot”
  - **ImageEnrichment step**:
    - On enter (or via a primary button), call “resume images”
    - Show stage viz for full pipeline (`composites/extract/assign/write`)
    - Allow user to continue to Agent without waiting (voice-only doesn’t need images)

### 2) Admin app API client: support fast vs resume

Update [apps/admin/lib/providers/tenant_providers.dart](apps/admin/lib/providers/tenant_providers.dart):

- Extend `triggerIngest(sessionId)` to accept an optional mode:
  - `mode='menu_only'` for Step 2
- Add `resumeIngestImages(sessionId)` for Step 3

### 3) Onboarding-service: expose fast trigger + resume endpoints

Update [backend/services/onboarding/src/index.ts](backend/services/onboarding/src/index.ts):

- Modify `POST /onboarding-sessions/:id/ingest-menu` to accept `{ mode: 'menu_only' | 'full' }` (default `menu_only` or `full`—pick based on desired UX; for this step-split, Step 2 will pass `menu_only`).
- Add `POST /onboarding-sessions/:id/ingest-menu/resume-images`:
  - Read the latest `job_id` from the session
  - Update `menus_ingest/{jobId}` with:
    - `pipelineMode='full'`
    - `status='queued'`
    - `resumeRequestedAt=now`
    - progress fields reset (best-effort)
  - Publish Pub/Sub message `{jobId}`

### 4) Menu-ingestion: add per-job mode + allow resume

Update [backend/services/menu-ingestion/src/types.ts](backend/services/menu-ingestion/src/types.ts):

- Extend `IngestJob` with optional fields:
  - `pipelineMode?: 'menu_only' | 'full'`
  - `resumeRequestedAt?: number`
  - (optional) `readyKind?: 'menu_only' | 'full'` for debugging

Update [backend/services/menu-ingestion/src/routes/tasks.ts](backend/services/menu-ingestion/src/routes/tasks.ts):

- **Resume-safe delivery guard**: adjust the “skip if processed/ready” logic to allow reprocessing when `resumeRequestedAt` indicates a resume is requested.
- **Fast path**:
  - Run analysis + prompt-v2 normalization
  - Write `menus_drafts/{jobId}`
  - Mark job `readyKind='menu_only'`, `status='ready'`, `progressStage='done'`
- **Full path**:
  - If a draft exists, load it and use it as `menuFromOriginal`.
  - Run `generateComposites` / `extractItemsFromComposites` / `assignThumbsToMenu`.
  - Merge image URLs into draft items and write back.
  - Mark job `readyKind='full'`, `status='ready'`, `progressStage='done'`

### 5) Keep prompt-v2 work integrated

The existing prompt-v2 plan remains, but the key adjustment is:

- The **FastIngestion step** must still produce the final structured menu (`modifierGroups`/`bundleRules`) because that’s what the voice agent needs.
- The ImageEnrichment step should only enrich images, not change item identity/structure.

## Acceptance criteria

- **Demo**: Upload pages → run Step 2 → Publish menu → Agent can read `/menu/snapshot` and order.
- Step 2 completes quickly (no `gemini-3-pro-image-preview` calls).
- Step 3 can be started later and eventually enriches `imageUrl/photoUrl` for menu items without changing item IDs/names.

## Files expected to change

- [apps/admin/lib/features/onboarding/onboarding_screen.dart](apps/admin/lib/features/onboarding/onboarding_screen.dart)
- [apps/admin/lib/providers/tenant_providers.dart](apps/admin/lib/providers/tenant_providers.dart)
- [backend/services/onboarding/src/index.ts](backend/services/onboarding/src/index.ts)
- [backend/services/menu-ingestion/src/types.ts](backend/services/menu-ingestion/src/types.ts)
- [backend/services/menu-ingestion/src/routes/tasks.ts](backend/services/menu-ingestion/src/routes/tasks.ts)