resource "google_pubsub_topic" "dispatch_events_dlq" {
  name    = "dispatch-events-dlq"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "notification-service"
  }
}

# Push subscription from dispatch-service -> notification-service for driver/customer comms.
resource "google_pubsub_subscription" "dispatch_to_notification" {
  name    = "dispatch-to-notification-${var.environment_name}"
  topic   = module.core.pubsub_topics["dispatch-events"]
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.notification_service}/events/dispatch"
    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.notification_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dispatch_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.notification_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}

resource "google_pubsub_topic" "deliveries_events_dlq" {
  name    = "deliveries-events-dlq"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "notification-service"
  }
}

# Push subscription from delivery-service -> notification-service for customer delivery updates.
resource "google_pubsub_subscription" "deliveries_to_notification" {
  name    = "deliveries-to-notification-${var.environment_name}"
  topic   = module.core.pubsub_topics["deliveries-events"]
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.notification_service}/events/deliveries"
    oidc_token {
      service_account_email = module.orders_events_push_sa.email
      audience              = local.service_urls.notification_service
    }
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.deliveries_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    module.notification_service,
    google_service_account_iam_member.orders_events_pubsub_token_creator
  ]
}
