resource "google_pubsub_topic" "menu_updates" {
  name    = "menu-updates"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_pubsub_topic_iam_member" "menu_updates_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.menu_updates.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.menu_ingestion_sa.email}"
}

resource "google_pubsub_subscription" "menu_updates_to_order_service" {
  name    = "menu-updates-to-order-service"
  topic   = google_pubsub_topic.menu_updates.name
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.order_service}/events/menu-updates"
    oidc_token {
      service_account_email = module.order_service_sa.email
    }
  }

  ack_deadline_seconds = 20
}

resource "google_pubsub_subscription" "menu_updates_to_voice_worker" {
  name    = "menu-updates-to-voice-worker"
  topic   = google_pubsub_topic.menu_updates.name
  project = var.project_id

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"
}
