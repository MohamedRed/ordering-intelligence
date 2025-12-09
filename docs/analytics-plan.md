# Analytics Plan (Draft)

## Data sources
- Firestore orders -> BigQuery (scheduled export or Dataflow).
- Pub/Sub order events -> BigQuery via subscription sink.
- Notification delivery logs -> BigQuery (structured logs ingestion).

## Metrics
- Order volume, status funnel, completion rates.
- Notification success/fail by channel.
- Agent call duration, ASR/LLM latency (future when available).

## Admin app integration
- Add endpoints (or direct BQ) to surface daily aggregates for dashboard.
- Replace static dashboard cards with BQ-backed summaries.

## TODO
- Define BQ schema and views.
- Add scheduled job/export wiring (Terraform/Dataflow).
- Add Looker Studio dashboard pulling from BQ.
