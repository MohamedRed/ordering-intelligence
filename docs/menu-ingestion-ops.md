# Menu Ingestion Ops

## Monitoring
- Alert: `menu_ingestion_backlog` policy (Terraform `infra/terraform/monitoring_ingestion.tf`) fires when `menu-ingest-push` undelivered messages > threshold for 10m. Wire `alert_channel_ids` to email/PagerDuty.
- Logs to watch: Cloud Run `menu-ingestion` for repeated "ingest failed" or Gemini 429s; Pub/Sub DLQ (if configured).

## Cleanup
- Endpoint: `POST /tasks/cleanup` (no auth by default; protect with IAP/proxy) resets `processing` jobs whose `processingExpiresAt` has passed back to `queued`. Schedule hourly via Cloud Scheduler:
  ```
  gcloud scheduler jobs create http menu-ingestion-cleanup \
    --schedule="0 * * * *" \
    --uri="https://MENU_INGESTION_URL/tasks/cleanup" \
    --http-method=POST \
    --oidc-service-account-email=menu-ingestion@PROJECT_ID.iam.gserviceaccount.com
  ```

## Quotas / Cost
- Default caps: `MENU_MAX_PAGES`=5, `MENU_MAX_ITEMS_PER_PAGE`=40, `MENU_MAX_TOTAL_ITEMS`=120.
- Gemini image calls are the main cost driver—keep caps conservative; monitor Pub/Sub backlog and job counts.

## Pub/Sub
- Topics: `menu-ingest` (push to /tasks/process), `menu-updates` (push to order-service, pull to voice-agent-worker).
- Subs: `menu-ingest-push`, `menu-updates-to-order-service`, `menu-updates-to-voice-worker-*`. Ensure they exist per env after Terraform apply.
