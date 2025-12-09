# Infra Notes (Pending Implementation)

## Pub/Sub
- Create subscription to `orders` topic targeting notification-service `/events/orders`.
- Use push subscription with OIDC token (service account of notification-service) for auth.
- Enable dead letter policy for failed deliveries.
- Terraform stubs: `infra/terraform/pubsub_orders_subscription.tf`, `pubsub_orders_dlq.tf`, and vars in `variables_notification.tf`.

## Metrics
- Scrape `/metrics` from order-service and notification-service (Prometheus/OpenTelemetry scraper).
- Add alerts: order_service_errors, notification_failures, auth_failures.
- Consider annotating scrape config in Terraform once collector is defined.
- CI preflight script: `tests/pubsub_subscription_test.sh` verifies envs before applying Pub/Sub subscription (no deploy).

## Firestore rules
- New rules added under `backend/services/order-service/firestore.rules` and `backend/services/notification-service/firestore.rules`. Deploy via Firebase CLI or gcloud.

## Buckets / retention
- Set GCS bucket TTL for transcripts/audio; target 13 months. Apply uniform bucket-level access and CMEK if required.

## CI/CD
- Add steps: `npm test` for notification-service, `go test ./...` for services, `flutter test` for apps, lint, and deploy rules.

## Secrets
- Store GOOGLE_APPLICATION_CREDENTIALS in Secret Manager; inject via Cloud Run/Cloud Functions env.
- Set ORDER_SERVICE_URL, ADMIN_SERVICE_URL, NOTIFICATION_SERVICE_URL, STORE_ID per env.
