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
      # Use the dedicated push SA (also used by other orders-events subscribers).
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.notification_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.notification_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

# Push subscription from order-service -> channel-comms for outbound channel updates.
resource "google_pubsub_subscription" "orders_to_channel_comms" {
  name    = "orders-to-channel-comms-${var.environment_name}"
  topic   = module.core.pubsub_topics["orders-events"]
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.channel_comms}/events/orders"
    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.channel_comms
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.channel_comms,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

# BigQuery sink for DLQ inspection/troubleshooting.
resource "google_bigquery_dataset" "orders_events_dlq" {
  dataset_id = "orders_events_dlq"
  project    = var.project_id
  location   = var.region

  access {
    role          = "WRITER"
    user_by_email = "service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  }

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "OWNER"
    user_by_email = "livvemap@gmail.com"
  }
}

resource "google_bigquery_table" "orders_events_dlq_messages" {
  dataset_id          = google_bigquery_dataset.orders_events_dlq.dataset_id
  project             = var.project_id
  table_id            = "messages"
  deletion_protection = false

  schema = jsonencode([
    { "name" : "data", "type" : "BYTES", "mode" : "NULLABLE" },
    { "name" : "attributes", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "message_id", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "publish_time", "type" : "TIMESTAMP", "mode" : "NULLABLE" },
    { "name" : "ordering_key", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "delivery_attempt", "type" : "INTEGER", "mode" : "NULLABLE" },
    { "name" : "subscription_name", "type" : "STRING", "mode" : "NULLABLE" }
  ])
}

resource "google_pubsub_subscription" "orders_events_dlq_bq" {
  name    = "orders-events-dlq-bq"
  topic   = google_pubsub_topic.orders_events_dlq.name
  project = var.project_id

  bigquery_config {
    table            = "${var.project_id}:${google_bigquery_dataset.orders_events_dlq.dataset_id}.messages"
    use_topic_schema = false
    write_metadata   = true
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"
}
