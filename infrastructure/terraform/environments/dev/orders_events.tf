resource "google_pubsub_topic" "orders_events_dlq" {
  name    = "orders-events-dlq"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "notification-service"
  }
}

# Push subscription from order-service -> notification-service with DLQ to avoid silent drops.
resource "google_pubsub_subscription" "orders_to_notification" {
  name    = "orders-to-notification-${var.environment_name}"
  topic   = module.core.pubsub_topics["orders-events"]
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.notification_service}/events/orders"
    oidc_token {
      # Re-use order-service SA (already provisioned) to authenticate Pub/Sub push.
      service_account_email = module.order_service_sa.email
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.name
    max_delivery_attempts = 10
  }
}

# BigQuery sink for DLQ inspection/troubleshooting.
resource "google_bigquery_dataset" "orders_events_dlq" {
  dataset_id = "orders_events_dlq"
  project    = var.project_id
  location   = var.region
}

resource "google_pubsub_subscription" "orders_events_dlq_bq" {
  name    = "orders-events-dlq-bq"
  topic   = google_pubsub_topic.orders_events_dlq.name
  project = var.project_id

  bigquery_config {
    table            = "${google_bigquery_dataset.orders_events_dlq.dataset_id}.messages"
    use_topic_schema = false
    write_metadata   = true
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"
}
