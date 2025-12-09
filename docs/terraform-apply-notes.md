# Terraform Apply Notes (menu ingestion + orders-events hardening)

Scope: recent additions for menu ingestion safety (DLQ, cleanup scheduler, voice-worker menu updates, monitoring) and orders-events → notification DLQ hardening.

## What was added
- Topics/subs: `menu-updates` (push to order-service, pull to voice-agent-worker), `menu-ingest-dlq` with DLQ policy on `menu-ingest-push`.
- BigQuery sink: `menu_ingest_dlq.messages` captures DLQ payloads.
- Cleanup: Cloud Scheduler job hits `/tasks/cleanup` hourly.
- Monitoring: `menu_ingestion_backlog` alert, `menu_ingest_dlq` alert, Gemini cost dashboard.
- Orders-events DLQ: topic `orders-events-dlq`, push sub `orders-to-notification-<env>` with dead-letter policy, and BigQuery sink `orders_events_dlq.messages`.

## Per-environment apply
From `infrastructure/terraform/environments/<env>`:
```bash
terraform init -backend=false   # if backend already configured, drop -backend=false
terraform plan   # review
terraform apply
```
Apply in order: dev → staging → prod.

## Post-apply checklist
- Verify subs:
  - `menu-ingest-push` has DLQ `menu-ingest-dlq`
  - `menu-updates-to-order-service` push
  - `menu-updates-to-voice-worker-*` pull
  - `menu-ingest-dlq-bq` exists and is delivering to `menu_ingest_dlq.messages`
  - `orders-to-notification-<env>` exists with DLQ `orders-events-dlq`
  - `orders-events-dlq-bq` exists and is delivering to `orders_events_dlq.messages`
- Scheduler: `menu-ingestion-cleanup` job present and enabled.
- Dashboard: “Menu Ingestion / Gemini Cost Guard” visible in Monitoring.
- Alerts: `menu_ingestion_backlog` and `menu_ingest_dlq` wired to `alert_channel_ids`.

## Runtime envs to set on deploy
- Voice-agent-worker:
  - `MENU_UPDATES_SUBSCRIPTION` = `menu-updates-to-voice-worker-[dev|staging|prod]`
  - `ORDER_SERVICE_URL`, `STORE_ID`
- Menu-ingestion (already in Terraform env): `MENU_MAX_PAGES`, `MENU_MAX_ITEMS_PER_PAGE`, `MENU_MAX_TOTAL_ITEMS` if you need different caps.

## Inspecting DLQ
```sql
SELECT * FROM `your-project.menu_ingest_dlq.messages`
ORDER BY publish_time DESC
LIMIT 50;
```

## Rollback
- To disable DLQ or cleanup temporarily, comment the resources in env tf files and `terraform apply`.
