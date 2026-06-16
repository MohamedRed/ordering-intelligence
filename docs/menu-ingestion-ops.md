# Menu Ingestion Ops

## Monitoring
- Alert: `menu_ingestion_backlog` policy (Terraform `infra/terraform/monitoring_ingestion.tf`) fires when `menu-ingest-push` undelivered messages > threshold for 10m. Wire `alert_channel_ids` to email/PagerDuty.
- Logs to watch: Cloud Run `menu-ingestion` for repeated "ingest failed" or Gemini 429s; Pub/Sub DLQ (if configured).

## Auth
- All endpoints except `/health` require bearer auth.
- Admin/browser calls use Firebase ID tokens.
- Pub/Sub push, Cloud Scheduler, and CI/ops calls use Google OIDC ID tokens when `ALLOW_GOOGLE_ID_TOKENS=true`.
- Set `GOOGLE_ID_TOKEN_AUDIENCES` to the menu-ingestion base URL and include only trusted service-account emails in `GOOGLE_ID_TOKEN_ALLOWED_EMAILS`.
- Staging and production must set explicit `MENU_INGESTION_CORS_ORIGINS`; wildcard CORS is rejected at startup.

## Cleanup
- Endpoint: `POST /tasks/cleanup` resets `processing` jobs whose `processingExpiresAt` has passed back to `queued`. Schedule hourly via Cloud Scheduler with an OIDC token whose audience matches `GOOGLE_ID_TOKEN_AUDIENCES`:
  ```
  gcloud scheduler jobs create http menu-ingestion-cleanup \
    --schedule="0 * * * *" \
    --uri="https://MENU_INGESTION_URL/tasks/cleanup" \
    --http-method=POST \
    --oidc-service-account-email=menu-ingestion@PROJECT_ID.iam.gserviceaccount.com \
    --oidc-token-audience="https://MENU_INGESTION_URL"
  ```

## Quotas / Cost
- Default caps: `MENU_MAX_PAGES`=5, `MENU_MAX_ITEMS_PER_PAGE`=40, `MENU_MAX_TOTAL_ITEMS`=120.
- Default image quality gates: `MENU_MIN_IMAGE_SHORT_EDGE`=600, `MENU_MIN_IMAGE_LONG_EDGE`=800, `MENU_MAX_IMAGE_PIXELS`=25000000, `MENU_MIN_LAPLACIAN_VARIANCE`=25.
- Gemini image calls are the main cost driver—keep caps conservative; monitor Pub/Sub backlog and job counts.

## Pub/Sub
- Topics: `menu-ingest` (push to /tasks/process), `menu-updates` (push to order-service, pull to voice-agent-worker).
- Subs: `menu-ingest-push`, `menu-updates-to-order-service`, `menu-updates-to-voice-worker-*`. Ensure they exist per env after Terraform apply.
