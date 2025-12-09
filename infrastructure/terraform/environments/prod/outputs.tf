output "menu_ingestion_base_url" {
  description = "Cloud Run URL for the menu-ingestion service"
  value       = local.service_urls.menu_ingestion
}

output "menu_ingestion_bucket" {
  description = "GCS bucket storing raw menu uploads"
  value       = google_storage_bucket.menu_ingestion.name
}

output "menu_ingestion_topic" {
  description = "Pub/Sub topic for menu ingestion jobs"
  value       = google_pubsub_topic.menu_ingest.name
}

output "menu_updates_topic" {
  description = "Pub/Sub topic for menu update fan-out"
  value       = google_pubsub_topic.menu_updates.name
}

output "menu_updates_push_subscription" {
  description = "Push subscription delivering menu updates to order-service"
  value       = google_pubsub_subscription.menu_updates_to_order_service.name
}

output "menu_updates_voice_worker_subscription" {
  description = "Pull subscription for voice-agent-worker to refresh menus"
  value       = google_pubsub_subscription.menu_updates_to_voice_worker.name
}

output "menu_ingest_dlq_bq_table" {
  description = "BigQuery table receiving menu-ingest DLQ messages"
  value       = google_pubsub_subscription.menu_ingest_dlq_bq.id
}
