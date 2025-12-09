# Observability Configuration

## Dashboards
- **LiveKit SIP & Voice Agent**: Track dispatch matches, call success rate, agent turn latency, and room cleanup confirmations (via LiveKit Cloud dashboards + exported logs).
- **Order Service**: HTTP latency/5xx metrics, Pub/Sub publishing success, Firestore write throughput.
- **Notification Service**: Push/SMS/Email delivery success ratios, retry queue depth.

## Alert Policies
- `voice-agent-session-errors`: Triggers when LiveKit deploy logs report repeated failures per region.
- `order-service-http-5xx`: Alerts when >5% 5xx for 5 minutes.
- `voice-agent-handoff-spike`: Alerts when handoff ratio >20% for any tenant within 30 minutes.
- `orders-pubsub-backlog`: Pub/Sub subscription oldest unacked message age > 2 minutes.

## Logging Standards
- Include `tenantId`, `callSessionId`, and `traceId` in structured logs.
- Use severity levels (`INFO`, `WARNING`, `ERROR`, `CRITICAL`).
- Redact PII before logging (customer phone numbers truncated).

## Metrics Export
- Enable Cloud Monitoring metric export to BigQuery for historical trend analysis.
- Configure Slack/PagerDuty integration via Cloud Monitoring notification channels.

## Terraform Module
- The legacy module `infrastructure/terraform/modules/observability` targeted the retired Cloud Run services. Monitoring for LiveKit-hosted agents now lives in LiveKit Cloud; use `modules/observability` only if you need additional GCP dashboards for order/notification services.
