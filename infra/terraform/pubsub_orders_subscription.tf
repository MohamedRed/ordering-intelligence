resource "google_pubsub_subscription" "orders_to_notification" {
  name  = "orders-to-notification"
  topic = google_pubsub_topic.orders.id

  push_config {
    push_endpoint = var.notification_service_push_endpoint # e.g. https://notification-service.prod/events/orders
    oidc_token {
      service_account_email = var.notification_service_sa_email
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_dlq.id
    max_delivery_attempts = 10
  }

  ack_deadline_seconds = 20
}
